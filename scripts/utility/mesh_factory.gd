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
## `inside` is the point the face should turn its back on. It defaults to the
## shape's origin, which is correct for anything star-shaped about that origin -
## boxes, crystals, rocks, columns. A torus or a tube is NOT star-shaped, so
## those pass the nearest point on their own axis instead (and, for an inner
## wall, a point outside it), which is what lets the same solved-winding rule
## keep working for hollow shapes.
static func _add_polygon(st: SurfaceTool, points: Array, inside: Vector3 = Vector3.ZERO) -> void:
	if points.size() < 3:
		return

	var centroid := Vector3.ZERO
	for p in points:
		centroid += p
	centroid /= float(points.size())
	var outward := centroid - inside

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
	# Degeneracy has to be judged RELATIVE TO THE POLYGON'S OWN SIZE. The first
	# version compared Newell's normal against a fixed 1e-6, which is an area
	# threshold in square metres: a legitimate 2 cm x 1 cm quad - every quad in
	# a small torus, and the blaster's trigger guard - fell under it and was
	# silently dropped. Enough of them dropped and the "mesh" came out with no
	# vertices at all, which then made `generate_tangents` fail and produced a
	# surface-less ArrayMesh that renders as nothing and reports no error.
	# Newell's normal has length 2 x area, so comparing it against the fourth
	# power of the polygon's own radius makes the test scale-free.
	var span := 0.0
	for p in points:
		span = maxf(span, (p as Vector3).distance_squared_to(centroid))
	if normal.length_squared() < span * span * 1e-8:
		return
	normal = normal.normalized()

	var ordered: Array = points.duplicate()
	if normal.dot(outward) < 0.0:
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
	# `generate_tangents` raises an engine error on an empty surface, and
	# `commit` then hands back a mesh with no surfaces that renders as nothing
	# at all. That is always a builder bug, so it is reported here rather than
	# left to be noticed in a screenshot weeks later.
	if st.get_aabb().size == Vector3.ZERO:
		push_error("MeshFactory: a builder produced an empty surface")
		return ArrayMesh.new()
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
		rings: int = 4, segments: int = 6) -> ArrayMesh:
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
			var jitter := 1.0 + rng.randf_range(-0.32, 0.28)
			var point: Vector3 = unit * jitter * size * 0.5
			# Flatten the underside. A boulder generated as a jittered sphere is
			# a potato: it has no base, so it never looks like it is resting on
			# the ground, only like it is floating just above it. Clamping the
			# bottom keeps the shape star-shaped about its centre, so the
			# solved-winding rule still holds.
			point.y = maxf(point.y, -size.y * 0.32)
			row.append(point)
		grid.append(row)

	# Collapse the poles so the tip is a point rather than a fan of near-
	# identical vertices at slightly different radii.
	var top: Vector3 = Vector3(0.0, size.y * 0.5 * (1.0 + rng.randf_range(-0.1, 0.1)), 0.0)
	var bottom: Vector3 = Vector3(0.0, -size.y * 0.32, 0.0)

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


# ==========================================================================
# Sphere
# ==========================================================================

## A faceted sphere. Rings and segments are deliberately low: this is the
## helmet, the Sentinel's core and every joint in the game, and it should read
## as cut facets rather than as a smooth ball rendered badly.
static func sphere(radius: float = 0.5, rings: int = 6, segments: int = 10,
		squash: Vector3 = Vector3.ONE) -> ArrayMesh:
	var key := "sph:%.3f,%d,%d,%.2f,%.2f,%.2f" % [
		radius, rings, segments, squash.x, squash.y, squash.z]
	return _cached(key, func() -> ArrayMesh:
		return _build_sphere(radius, rings, segments, squash))


static func _build_sphere(radius: float, rings: int, segments: int,
		squash: Vector3) -> ArrayMesh:
	var ring_count: int = maxi(rings, 2)
	var segment_count: int = maxi(segments, 3)

	var grid: Array = []
	for r in range(ring_count + 1):
		var phi := PI * float(r) / float(ring_count)
		var row: Array = []
		for sg in range(segment_count):
			var theta := TAU * float(sg) / float(segment_count)
			row.append(Vector3(
				sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * radius * squash)
		grid.append(row)

	var top := Vector3(0.0, radius * squash.y, 0.0)
	var bottom := Vector3(0.0, -radius * squash.y, 0.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in range(ring_count):
		for sg in range(segment_count):
			var s2 := (sg + 1) % segment_count
			var a: Vector3 = grid[r][sg]
			var b: Vector3 = grid[r][s2]
			var c: Vector3 = grid[r + 1][s2]
			var d: Vector3 = grid[r + 1][sg]
			if r == 0:
				_add_polygon(st, [top, c, d])
			elif r == ring_count - 1:
				_add_polygon(st, [a, b, bottom])
			else:
				_add_polygon(st, [a, b, c, d])
	return _commit(st)


# ==========================================================================
# Capsule
# ==========================================================================

## A cylinder with domed ends: every limb, and the barrel of the blaster.
## `height` is the total length including both caps, so a capsule of height 1
## occupies exactly one metre - the alternative convention (height excluding
## caps) makes every call site do arithmetic.
static func capsule(height: float = 1.0, radius: float = 0.2, sides: int = 8,
		cap_rings: int = 2) -> ArrayMesh:
	var key := "cap:%.3f,%.3f,%d,%d" % [height, radius, sides, cap_rings]
	return _cached(key, func() -> ArrayMesh:
		return _build_capsule(height, radius, sides, cap_rings))


static func _build_capsule(height: float, radius: float, sides: int,
		cap_rings: int) -> ArrayMesh:
	var n: int = maxi(sides, 3)
	var caps: int = maxi(cap_rings, 1)
	var r: float = minf(radius, height * 0.5)
	var half_shaft: float = maxf(height * 0.5 - r, 0.0)

	# Every ring of the silhouette from the bottom pole up, poles excluded.
	# A cap ring at angle phi (0 at the pole, 90 degrees at the equator) has
	# radius r*sin(phi) and sits r*cos(phi) beyond the end of the shaft.
	var rows: Array = []
	for c in range(1, caps + 1):
		var phi := PI * 0.5 * float(c) / float(caps)
		rows.append(_ring(n, r * sin(phi), -half_shaft - r * cos(phi)))
	if half_shaft > 0.0:
		rows.append(_ring(n, r, half_shaft))
	for c in range(caps - 1, 0, -1):
		var phi2 := PI * 0.5 * float(c) / float(caps)
		rows.append(_ring(n, r * sin(phi2), half_shaft + r * cos(phi2)))

	var bottom_pole := Vector3(0.0, -half_shaft - r, 0.0)
	var top_pole := Vector3(0.0, half_shaft + r, 0.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var first: Array = rows[0]
	var last: Array = rows[rows.size() - 1]
	for k in n:
		var k2 := (k + 1) % n
		_add_polygon(st, [bottom_pole, first[k2], first[k]])
		_add_polygon(st, [top_pole, last[k], last[k2]])
	for i in range(rows.size() - 1):
		var lower: Array = rows[i]
		var upper: Array = rows[i + 1]
		for k in n:
			var k2 := (k + 1) % n
			_add_polygon(st, [lower[k], lower[k2], upper[k2], upper[k]])
	return _commit(st)


## One horizontal ring of `n` points at radius `r`, height `y`.
static func _ring(n: int, r: float, y: float) -> Array:
	var points: Array = []
	for i in n:
		var angle := TAU * float(i) / float(n)
		points.append(Vector3(cos(angle) * r, y, sin(angle) * r))
	return points


# ==========================================================================
# Tube
# ==========================================================================

## A pipe: a cylinder with a hole down its axis, capped by an annulus at each
## end. Barrels, thruster nozzles and collars all want a visible bore - a solid
## cylinder pretending to be a barrel is the thing that makes a weapon read as
## a toy.
##
## The inner wall is where the "faces point away from the origin" rule stops
## working, so each inner quad is oriented against a point further out than
## itself instead. See `_add_polygon`.
static func tube(height: float = 1.0, outer_radius: float = 0.2,
		inner_radius: float = 0.12, sides: int = 10) -> ArrayMesh:
	var key := "tube:%.3f,%.3f,%.3f,%d" % [height, outer_radius, inner_radius, sides]
	return _cached(key, func() -> ArrayMesh:
		return _build_tube(height, outer_radius, inner_radius, sides))


static func _build_tube(height: float, outer_radius: float, inner_radius: float,
		sides: int) -> ArrayMesh:
	var n: int = maxi(sides, 3)
	var half := height * 0.5
	var outer: float = maxf(outer_radius, 0.001)
	var inner: float = clampf(inner_radius, 0.0, outer * 0.95)

	var ol: Array = _ring(n, outer, -half)
	var ou: Array = _ring(n, outer, half)
	var il: Array = _ring(n, inner, -half)
	var iu: Array = _ring(n, inner, half)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var j := (i + 1) % n
		# Outer wall: outward is away from the axis.
		_add_polygon(st, [ol[i], ol[j], ou[j], ou[i]], Vector3(0.0, ol[i].y, 0.0))
		# Inner wall: outward is TOWARDS the axis, so the reference point is
		# placed beyond the wall rather than inside it.
		var mid_in: Vector3 = (il[i] + il[j]) * 0.5
		_add_polygon(st, [iu[i], iu[j], il[j], il[i]], mid_in.normalized() * outer * 2.0)
		# Annulus at each end.
		_add_polygon(st, [ou[i], ou[j], iu[j], iu[i]], Vector3(0.0, 0.0, 0.0))
		_add_polygon(st, [il[i], il[j], ol[j], ol[i]], Vector3(0.0, 0.0, 0.0))
	return _commit(st)


# ==========================================================================
# Wedge
# ==========================================================================

## A right-angled ramp: `size.y` tall at -Z, tapering to nothing at +Z. Angled
## armour plates, cockpit noses, buttresses.
static func wedge(size: Vector3 = Vector3.ONE, taper: float = 0.0) -> ArrayMesh:
	var key := "wedge:%.3f,%.3f,%.3f,%.3f" % [size.x, size.y, size.z, taper]
	return _cached(key, func() -> ArrayMesh: return _build_wedge(size, taper))


static func _build_wedge(size: Vector3, taper: float) -> ArrayMesh:
	var h := size * 0.5
	# `taper` leaves a flat top of that fraction rather than a knife edge, which
	# is what stops a wedge reading as a doorstop.
	var top_y: float = -h.y + size.y * clampf(taper, 0.0, 1.0)
	var back_x: float = h.x * (0.35 + 0.65 * clampf(taper, 0.0, 1.0))

	var bl := Vector3(-h.x, -h.y, -h.z)
	var br := Vector3(h.x, -h.y, -h.z)
	var fr := Vector3(h.x, -h.y, h.z)
	var fl := Vector3(-h.x, -h.y, h.z)
	var tl := Vector3(-h.x, h.y, -h.z)
	var tr := Vector3(h.x, h.y, -h.z)
	var ttl := Vector3(-back_x, top_y, h.z)
	var ttr := Vector3(back_x, top_y, h.z)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_polygon(st, [bl, br, fr, fl])          # floor
	_add_polygon(st, [bl, tl, tr, br])          # tall back
	_add_polygon(st, [tl, ttl, ttr, tr])        # sloping top
	_add_polygon(st, [ttl, fl, fr, ttr])        # front face
	_add_polygon(st, [bl, fl, ttl, tl])         # left side
	_add_polygon(st, [br, tr, ttr, fr])         # right side
	return _commit(st)


# ==========================================================================
# Torus
# ==========================================================================

## A ring. Collars, hover rings, the Sentinel's armature.
##
## Not star-shaped about its origin, so each quad is oriented against the point
## on the major circle it wraps - the centre of its own tube cross-section.
static func torus(major_radius: float = 0.5, minor_radius: float = 0.12,
		major_segments: int = 14, minor_segments: int = 6) -> ArrayMesh:
	var key := "torus:%.3f,%.3f,%d,%d" % [
		major_radius, minor_radius, major_segments, minor_segments]
	return _cached(key, func() -> ArrayMesh:
		return _build_torus(major_radius, minor_radius, major_segments, minor_segments))


static func _build_torus(major_radius: float, minor_radius: float,
		major_segments: int, minor_segments: int) -> ArrayMesh:
	var big: int = maxi(major_segments, 3)
	var small: int = maxi(minor_segments, 3)

	var centres: Array = []
	var rings: Array = []
	for i in big:
		var a := TAU * float(i) / float(big)
		var centre := Vector3(cos(a) * major_radius, 0.0, sin(a) * major_radius)
		var outward := Vector3(cos(a), 0.0, sin(a))
		var row: Array = []
		for k in small:
			var b := TAU * float(k) / float(small)
			row.append(centre + outward * (cos(b) * minor_radius)
				+ Vector3(0.0, sin(b) * minor_radius, 0.0))
		centres.append(centre)
		rings.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in big:
		var j := (i + 1) % big
		var seam: Vector3 = (centres[i] + centres[j]) * 0.5
		for k in small:
			var k2 := (k + 1) % small
			_add_polygon(st, [rings[i][k], rings[i][k2], rings[j][k2], rings[j][k]], seam)
	return _commit(st)
