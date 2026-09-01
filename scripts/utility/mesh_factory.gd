extends RefCounted
class_name MeshFactory
## Procedurally built meshes, so the game has real geometry instead of raw
## engine primitives - and without bundling any third-party asset.
##
## WINDING IS SOLVED, NOT HAND-MANAGED
## Getting triangle winding right by hand across a chamfered box (6 faces, 12
## edge strips, 8 corner triangles) is where this kind of code normally breaks:
## one flipped quad becomes a hole you only notice from a particular angle.
## Instead, every polygon here is emitted through `_add_polygon`, which derives
## the outward direction from the shape's own centre and flips the order when it
## disagrees. Every shape below is star-shaped about its origin, so that test is
## always valid and a flipped face is not expressible.
##
## Everything is FLAT SHADED on purpose: per-face normals are what make faceted
## low-poly geometry read as deliberate rather than as a low-resolution attempt
## at something smooth.

## Meshes are shared between every block that asks for the same shape. A level
## of ~90 blocks would otherwise allocate ~90 near-identical meshes.
static var _cache: Dictionary = {}


static func _cached(key: String, builder: Callable) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var mesh: ArrayMesh = builder.call()
	_cache[key] = mesh
	return mesh


static func clear_cache() -> void:
	_cache.clear()


# ==========================================================================
# Polygon emission
# ==========================================================================

## Emits one convex polygon as a flat-shaded triangle fan, choosing the winding
## that faces away from the origin. `points` must be in order around the
## polygon; either direction is fine.
static func _add_polygon(st: SurfaceTool, points: Array) -> void:
	if points.size() < 3:
		return

	var centroid := Vector3.ZERO
	for p in points:
		centroid += p
	centroid /= float(points.size())

	# Newell's method: robust for any planar polygon, including the thin slivers
	# a large bevel produces, where a naive cross product of two edges can be
	# degenerate.
	var normal := Vector3.ZERO
	for i in points.size():
		var current: Vector3 = points[i]
		var next: Vector3 = points[(i + 1) % points.size()]
		normal.x += (current.y - next.y) * (current.z + next.z)
		normal.y += (current.z - next.z) * (current.x + next.x)
		normal.z += (current.x - next.x) * (current.y + next.y)
	if normal.length_squared() < 0.000001:
		return
	normal = normal.normalized()

	var ordered: Array = points.duplicate()
	if normal.dot(centroid) < 0.0:
		ordered.reverse()
		normal = -normal

	# Cheap planar UVs. Nothing here is textured, but a mesh with no UVs at all
	# limits what a material can later do with it.
	var u_axis := normal.cross(Vector3.UP)
	if u_axis.length_squared() < 0.001:
		u_axis = normal.cross(Vector3.FORWARD)
	u_axis = u_axis.normalized()
	var v_axis := normal.cross(u_axis).normalized()

	# `ordered` now runs counter-clockwise as seen from outside, which is the
	# OpenGL convention and the WRONG one here: Godot treats a CLOCKWISE
	# triangle as front-facing. Emitting the fan in the obvious order made every
	# mesh in the game inside-out - the outward faces were culled and what you
	# saw was the inside of the far side, whose normals point away from every
	# lamp in the room. It reads as "the level is too dark" rather than as a
	# geometry bug, which is why it survived so long: silhouettes, collision,
	# navigation and screenshots all look plausible. Verified against Godot's
	# own BoxMesh and PlaneMesh, where the right-hand-rule normal disagrees with
	# the stored normal on every single triangle, as it now does here.
	for i in range(1, ordered.size() - 1):
		for vertex in [ordered[0], ordered[i + 1], ordered[i]]:
			var v: Vector3 = vertex
			st.set_normal(normal)
			st.set_uv(Vector2(v.dot(u_axis), v.dot(v_axis)) * 0.5)
			st.add_vertex(v)


## Finishes a surface.
##
## A mesh that carries UVs should carry tangents to go with them; every builder
## commits through here so none of them can forget.
static func _commit(st: SurfaceTool) -> ArrayMesh:
	st.generate_tangents()
	return st.commit()


# ==========================================================================
# Chamfered box
# ==========================================================================

## A box with chamfered edges.
##
## This is the highest-value shape in the project: every wall, pillar, console
## and crate used a hard-edged BoxMesh, and hard edges give a renderer nothing
## to catch a highlight on - which is most of why the first screenshots read as
## flat grey slabs. A chamfer adds a lit sliver along every edge and costs 26
## polygons.
static func beveled_box(size: Vector3, bevel: float = 0.05) -> ArrayMesh:
	var key := "bbox:%.3f,%.3f,%.3f:%.3f" % [size.x, size.y, size.z, bevel]
	return _cached(key, func() -> ArrayMesh: return _build_beveled_box(size, bevel))


static func _build_beveled_box(size: Vector3, bevel: float) -> ArrayMesh:
	var h := size * 0.5
	# Never let the chamfer eat more than a third of the smallest side, or a
	# thin panel collapses into a wedge.
	var b: float = clampf(bevel, 0.0, minf(h.x, minf(h.y, h.z)) * 0.66)
	var inner := Vector3(h.x - b, h.y - b, h.z - b)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var signs := [-1.0, 1.0]

	# Three vertices per corner, one pulled out to each of the corner's faces.
	var corner := func(sx: float, sy: float, sz: float, axis: int) -> Vector3:
		match axis:
			0: return Vector3(sx * h.x, sy * inner.y, sz * inner.z)
			1: return Vector3(sx * inner.x, sy * h.y, sz * inner.z)
			_: return Vector3(sx * inner.x, sy * inner.y, sz * h.z)

	# --- 6 face quads ---
	for s in signs:
		_add_polygon(st, [
			corner.call(s, -1.0, -1.0, 0), corner.call(s, -1.0, 1.0, 0),
			corner.call(s, 1.0, 1.0, 0), corner.call(s, 1.0, -1.0, 0)])
		_add_polygon(st, [
			corner.call(-1.0, s, -1.0, 1), corner.call(-1.0, s, 1.0, 1),
			corner.call(1.0, s, 1.0, 1), corner.call(1.0, s, -1.0, 1)])
		_add_polygon(st, [
			corner.call(-1.0, -1.0, s, 2), corner.call(-1.0, 1.0, s, 2),
			corner.call(1.0, 1.0, s, 2), corner.call(1.0, -1.0, s, 2)])

	# --- 12 edge quads: one per pair of adjacent faces ---
	for a in signs:
		for c in signs:
			# Edges running along Z (join an X face to a Y face).
			_add_polygon(st, [
				corner.call(a, c, -1.0, 0), corner.call(a, c, 1.0, 0),
				corner.call(a, c, 1.0, 1), corner.call(a, c, -1.0, 1)])
			# Edges running along Y (join an X face to a Z face).
			_add_polygon(st, [
				corner.call(a, -1.0, c, 0), corner.call(a, 1.0, c, 0),
				corner.call(a, 1.0, c, 2), corner.call(a, -1.0, c, 2)])
			# Edges running along X (join a Y face to a Z face).
			_add_polygon(st, [
				corner.call(-1.0, a, c, 1), corner.call(1.0, a, c, 1),
				corner.call(1.0, a, c, 2), corner.call(-1.0, a, c, 2)])

	# --- 8 corner triangles ---
	for sx in signs:
		for sy in signs:
			for sz in signs:
				_add_polygon(st, [
					corner.call(sx, sy, sz, 0),
					corner.call(sx, sy, sz, 1),
					corner.call(sx, sy, sz, 2)])

	return _commit(st)


# ==========================================================================
# Crystal
# ==========================================================================

## A quartz-like crystal: a faceted prism with pyramidal caps.
##
## Replaces a PrismMesh, which is a triangular wedge and reads as a doorstop.
## The asymmetry between the two caps is deliberate - a perfectly symmetric
## crystal looks manufactured.
static func crystal(height: float = 1.0, radius: float = 0.28, sides: int = 6) -> ArrayMesh:
	var key := "crystal:%.3f,%.3f,%d" % [height, radius, sides]
	return _cached(key, func() -> ArrayMesh: return _build_crystal(height, radius, sides))


static func _build_crystal(height: float, radius: float, sides: int) -> ArrayMesh:
	var n: int = maxi(sides, 3)
	var half := height * 0.5
	var shoulder_low := -half * 0.45
	var shoulder_high := half * 0.35

	var lower: Array = []
	var upper: Array = []
	for i in n:
		var angle := TAU * float(i) / float(n)
		# Alternating radius gives the girdle uneven facet widths, the way a
		# real crystal grows.
		var r: float = radius * (1.0 if i % 2 == 0 else 0.86)
		var x := cos(angle) * r
		var z := sin(angle) * r
		lower.append(Vector3(x, shoulder_low, z))
		upper.append(Vector3(x, shoulder_high, z))

	var apex := Vector3(0.0, half, 0.0)
	var base := Vector3(0.0, -half, 0.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var j := (i + 1) % n
		_add_polygon(st, [lower[i], lower[j], upper[j], upper[i]])
		_add_polygon(st, [upper[i], upper[j], apex])
		_add_polygon(st, [lower[j], lower[i], base])
	return _commit(st)


# ==========================================================================
# Rock
# ==========================================================================

## A faceted boulder: a low-resolution sphere pushed in and out per vertex by a
## deterministic hash, so the same seed always yields the same rock and no two
## rocks in a level are identical.
##
## Stays star-shaped about its centre (displacement is radial and always
## positive), which keeps the winding rule above valid.
static func rock(size: Vector3 = Vector3.ONE, seed_value: int = 0,
		rings: int = 5, segments: int = 7) -> ArrayMesh:
	var key := "rock:%.2f,%.2f,%.2f:%d:%d,%d" % [size.x, size.y, size.z, seed_value, rings, segments]
	return _cached(key, func() -> ArrayMesh: return _build_rock(size, seed_value, rings, segments))


static func _build_rock(size: Vector3, seed_value: int, rings: int, segments: int) -> ArrayMesh:
	var ring_count: int = maxi(rings, 3)
	var segment_count: int = maxi(segments, 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# grid[ring][segment], with the poles as single points.
	var grid: Array = []
	for r in range(ring_count + 1):
		var phi := PI * float(r) / float(ring_count)
		var row: Array = []
		for s in range(segment_count):
			var theta := TAU * float(s) / float(segment_count)
			var unit := Vector3(
				sin(phi) * cos(theta),
				cos(phi),
				sin(phi) * sin(theta))
			var jitter := 1.0 + rng.randf_range(-0.22, 0.22)
			row.append(unit * jitter * size * 0.5)
		grid.append(row)

	# Collapse the poles so the tip is a point rather than a fan of near-
	# identical vertices at slightly different radii.
	var top: Vector3 = Vector3(0.0, size.y * 0.5 * (1.0 + rng.randf_range(-0.1, 0.1)), 0.0)
	var bottom: Vector3 = Vector3(0.0, -size.y * 0.5 * (1.0 + rng.randf_range(-0.1, 0.1)), 0.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in range(ring_count):
		for s in range(segment_count):
			var s2 := (s + 1) % segment_count
			var a: Vector3 = grid[r][s]
			var b: Vector3 = grid[r][s2]
			var c: Vector3 = grid[r + 1][s2]
			var d: Vector3 = grid[r + 1][s]
			if r == 0:
				_add_polygon(st, [top, c, d])
			elif r == ring_count - 1:
				_add_polygon(st, [a, b, bottom])
			else:
				_add_polygon(st, [a, b, c, d])
	return _commit(st)


# ==========================================================================
# Tapered column
# ==========================================================================

## A faceted column that narrows towards the top, for pillars and pedestals.
static func tapered_column(height: float, bottom_radius: float, top_radius: float,
		sides: int = 8) -> ArrayMesh:
	var key := "col:%.3f,%.3f,%.3f,%d" % [height, bottom_radius, top_radius, sides]
	return _cached(key, func() -> ArrayMesh:
		return _build_tapered_column(height, bottom_radius, top_radius, sides))


static func _build_tapered_column(height: float, bottom_radius: float,
		top_radius: float, sides: int) -> ArrayMesh:
	var n: int = maxi(sides, 3)
	var half := height * 0.5
	var lower: Array = []
	var upper: Array = []
	for i in n:
		var angle := TAU * float(i) / float(n)
		lower.append(Vector3(cos(angle) * bottom_radius, -half, sin(angle) * bottom_radius))
		upper.append(Vector3(cos(angle) * top_radius, half, sin(angle) * top_radius))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var j := (i + 1) % n
		_add_polygon(st, [lower[i], lower[j], upper[j], upper[i]])
	_add_polygon(st, upper)
	var reversed_lower: Array = lower.duplicate()
	reversed_lower.reverse()
	_add_polygon(st, reversed_lower)
	return _commit(st)
