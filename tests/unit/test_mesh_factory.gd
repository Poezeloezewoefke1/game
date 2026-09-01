extends TestCase
## Structural checks on the procedurally built meshes.
##
## A rendered screenshot is how these are judged for looks, but a screenshot
## cannot be run in CI and cannot tell you that a mesh has inverted normals,
## the wrong size, or a hole where a face should be. These assertions cover the
## parts that ARE objectively checkable: extent, surface count, watertightness
## by triangle count, normal validity, and determinism.


func _surface_arrays(mesh: ArrayMesh) -> Array:
	return mesh.surface_get_arrays(0)


func _check_mesh_sane(mesh: ArrayMesh, label: String) -> void:
	if not check(mesh != null, "%s: a mesh was produced" % label):
		return
	check_eq(mesh.get_surface_count(), 1, "%s: exactly one surface" % label)
	var arrays := _surface_arrays(mesh)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	check(vertices.size() >= 3, "%s: has vertices (%d)" % [label, vertices.size()])
	check_eq(vertices.size() % 3, 0, "%s: vertex count is a whole number of triangles" % label)
	check_eq(normals.size(), vertices.size(), "%s: every vertex has a normal" % label)

	var bad_vertices := 0
	for v in vertices:
		if not v.is_finite():
			bad_vertices += 1
	check_eq(bad_vertices, 0, "%s: no non-finite vertex" % label)

	var bad_normals := 0
	for n in normals:
		if not n.is_finite() or absf(n.length() - 1.0) > 0.01:
			bad_normals += 1
	check_eq(bad_normals, 0, "%s: every normal is finite and unit length" % label)


## Every shape here is star-shaped about its origin, so a correctly wound face
## has a normal pointing away from the centre. A single flipped triangle - the
## classic hand-wound-geometry bug - shows up here as a hole at runtime.
## Two separate things have to be true, and the difference between them cost a
## long hunt:
##
##   1. the triangle is wound the way Godot wants it, and
##   2. for a SOLID shape, the stored normal points away from the origin.
##
## (1) applies to everything. The original version of this helper only checked
## (2), which is true by construction in the builder and therefore could never
## have failed - while (1) was wrong for every triangle in the project. Godot
## treats a CLOCKWISE triangle as front-facing, so the right-hand-rule normal of
## a correctly wound triangle points INWARD, opposite to the stored normal.
## Getting that backwards renders every mesh inside-out, visible only as "the
## game is too dark", because you end up looking at the unlit inner surface of
## the far side.
##
## (2) is checked separately and only where it applies: a torus and a tube have
## surfaces that legitimately face the origin, and asserting otherwise would
## force the bore to be built solid.
##
## The expectation for (1) is not a guess: it is measured from Godot's own
## BoxMesh and PlaneMesh in `test_matches_godots_own_winding`.
func _check_outward_winding(mesh: ArrayMesh, label: String, solid: bool = true) -> void:
	var arrays := _surface_arrays(mesh)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var outward_normals := 0
	var wrong_winding := 0
	var total := 0
	for i in range(0, vertices.size(), 3):
		var a: Vector3 = vertices[i]
		var b: Vector3 = vertices[i + 1]
		var c: Vector3 = vertices[i + 2]
		var centre: Vector3 = (a + b + c) / 3.0
		var geometric: Vector3 = (b - a).cross(c - a)
		if geometric.length_squared() < 1e-12:
			continue
		total += 1
		if solid and centre.length_squared() > 0.0001 \
				and normals[i].dot(centre.normalized()) < -0.05:
			outward_normals += 1
		if geometric.normalized().dot(normals[i]) > 0.0:
			wrong_winding += 1
	if solid:
		check_eq(outward_normals, 0, "%s: every stored normal points outward (%d of %d wrong)" % [
			label, outward_normals, total])
	check_eq(wrong_winding, 0,
		"%s: every triangle is wound clockwise from outside, as Godot requires "
		% label + "(%d of %d wrong)" % [wrong_winding, total])


func test_matches_godots_own_winding() -> void:
	# The convention is not written down anywhere in this project's control, so
	# it is read back off the engine. If a future Godot flips it, this fails
	# first and explains why everything went dark.
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.0, 2.0)
	check_eq(_winding_agreements(box), 0,
		"Godot's own BoxMesh winds so the right-hand-rule normal opposes the stored one")
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	check_eq(_winding_agreements(plane), 0, "and so does its PlaneMesh")
	check_eq(_winding_agreements(MeshFactory.beveled_box(Vector3(2.0, 1.0, 2.0), 0.1)), 0,
		"and so does every mesh this project builds")


## Number of triangles whose right-hand-rule normal agrees with the stored
## normal. For a Godot-correct mesh this is zero.
func _winding_agreements(mesh: Mesh) -> int:
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	# An unindexed surface leaves this slot null rather than empty.
	var raw_index: Variant = arrays[Mesh.ARRAY_INDEX]
	var index: PackedInt32Array = (raw_index if raw_index != null
		else PackedInt32Array())
	var count: int = index.size() if index.size() > 0 else v.size()
	var agreements := 0
	for t in range(0, count, 3):
		var i0: int = index[t] if index.size() > 0 else t
		var i1: int = index[t + 1] if index.size() > 0 else t + 1
		var i2: int = index[t + 2] if index.size() > 0 else t + 2
		var geometric: Vector3 = (v[i1] - v[i0]).cross(v[i2] - v[i0])
		if geometric.length_squared() < 1e-9:
			continue
		if geometric.normalized().dot(n[i0]) > 0.0:
			agreements += 1
	return agreements


func test_beveled_box_dimensions() -> void:
	var size := Vector3(2.0, 1.0, 3.0)
	var mesh := MeshFactory.beveled_box(size, 0.1)
	_check_mesh_sane(mesh, "beveled box")
	_check_outward_winding(mesh, "beveled box")
	var aabb := mesh.get_aabb()
	check_near(aabb.size.x, size.x, 0.01, "beveled box width matches the requested size")
	check_near(aabb.size.y, size.y, 0.01, "beveled box height matches")
	check_near(aabb.size.z, size.z, 0.01, "beveled box depth matches")
	check_near(aabb.get_center().length(), 0.0, 0.01, "beveled box is centred on its origin")


func test_beveled_box_has_more_faces_than_a_plain_box() -> void:
	# 6 faces + 12 edge strips + 8 corners. If a future change silently falls
	# back to a plain box the chamfer disappears and nothing else would notice.
	var mesh := MeshFactory.beveled_box(Vector3.ONE, 0.08)
	var verts: PackedVector3Array = _surface_arrays(mesh)[Mesh.ARRAY_VERTEX]
	var triangles: int = verts.size() / 3
	check(triangles >= 24, "a chamfered box has far more than a box's 12 triangles (%d)" % triangles)


func test_bevel_cannot_eat_the_shape() -> void:
	# A chamfer wider than the block would invert it. Ask for an absurd one.
	var mesh := MeshFactory.beveled_box(Vector3(0.2, 0.2, 0.2), 5.0)
	_check_mesh_sane(mesh, "over-bevelled box")
	var aabb := mesh.get_aabb()
	check_near(aabb.size.x, 0.2, 0.01, "an over-large bevel is clamped, not applied")


func test_crystal_dimensions() -> void:
	var mesh := MeshFactory.crystal(2.0, 0.5, 6)
	_check_mesh_sane(mesh, "crystal")
	_check_outward_winding(mesh, "crystal")
	var aabb := mesh.get_aabb()
	check_near(aabb.size.y, 2.0, 0.01, "crystal height matches")
	check(aabb.size.x <= 1.01 and aabb.size.z <= 1.01,
		"crystal stays within twice its radius (%.2f x %.2f)" % [aabb.size.x, aabb.size.z])


func test_crystal_side_count_changes_geometry() -> void:
	var six: int = _surface_arrays(MeshFactory.crystal(1.0, 0.3, 6))[Mesh.ARRAY_VERTEX].size()
	var ten: int = _surface_arrays(MeshFactory.crystal(1.0, 0.3, 10))[Mesh.ARRAY_VERTEX].size()
	check(ten > six, "more sides produce more geometry (%d vs %d)" % [ten, six])


func test_rock_is_deterministic() -> void:
	# The same seed must give the same rock on every machine, or a scattered
	# level would differ between host and client.
	var a: PackedVector3Array = _surface_arrays(MeshFactory.rock(Vector3.ONE, 42))[Mesh.ARRAY_VERTEX]
	MeshFactory.clear_cache()
	var b: PackedVector3Array = _surface_arrays(MeshFactory.rock(Vector3.ONE, 42))[Mesh.ARRAY_VERTEX]
	check_eq(a.size(), b.size(), "the same seed yields the same vertex count")
	var differences := 0
	for i in a.size():
		if a[i].distance_to(b[i]) > 0.0001:
			differences += 1
	check_eq(differences, 0, "the same seed yields identical vertices")


func test_rock_seeds_differ() -> void:
	var a: PackedVector3Array = _surface_arrays(MeshFactory.rock(Vector3.ONE, 1))[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = _surface_arrays(MeshFactory.rock(Vector3.ONE, 2))[Mesh.ARRAY_VERTEX]
	var differences := 0
	for i in mini(a.size(), b.size()):
		if a[i].distance_to(b[i]) > 0.0001:
			differences += 1
	check(differences > 0, "different seeds yield different rocks")


func test_rock_stays_within_its_size() -> void:
	var mesh := MeshFactory.rock(Vector3(2.0, 2.0, 2.0), 9)
	_check_mesh_sane(mesh, "rock")
	_check_outward_winding(mesh, "rock")
	var aabb := mesh.get_aabb()
	# Jitter is +/-22%, so the extent must stay inside that envelope. A rock
	# that quietly grows past its declared size would clip through level walls.
	check(aabb.size.x <= 2.0 * 1.25, "rock width stays near its size (%.2f)" % aabb.size.x)
	check(aabb.size.y <= 2.0 * 1.25, "rock height stays near its size (%.2f)" % aabb.size.y)


func test_tapered_column() -> void:
	var mesh := MeshFactory.tapered_column(3.0, 1.0, 0.5, 8)
	_check_mesh_sane(mesh, "column")
	_check_outward_winding(mesh, "column")
	var aabb := mesh.get_aabb()
	check_near(aabb.size.y, 3.0, 0.01, "column height matches")
	check(aabb.size.x <= 2.01, "column is no wider than its base diameter")


func test_meshes_are_shared_not_reallocated() -> void:
	# A level of ~90 blocks must not allocate ~90 identical meshes.
	MeshFactory.clear_cache()
	var first := MeshFactory.beveled_box(Vector3(1.0, 2.0, 3.0), 0.05)
	var second := MeshFactory.beveled_box(Vector3(1.0, 2.0, 3.0), 0.05)
	check(first == second, "identical requests return the same shared mesh")
	var different := MeshFactory.beveled_box(Vector3(1.0, 2.0, 4.0), 0.05)
	check(first != different, "a different size returns a different mesh")


func test_small_shapes_are_not_silently_empty() -> void:
	# THE REGRESSION THIS GUARDS. `_add_polygon` judged degeneracy against a
	# fixed area epsilon of 1e-6 square metres. A 2 cm x 1 cm quad is under
	# that, so every quad in a small torus was discarded, the surface came out
	# with no vertices, and the builder returned an ArrayMesh with NO SURFACES.
	# It renders as nothing and reports nothing. Two parts of the blaster and
	# several fittings on the suit were simply absent for a whole session.
	#
	# Sizes below are the real ones from the weapon, the suit and the props.
	var cases: Array = [
		["blaster coil", MeshFactory.torus(0.058, 0.013, 14, 6), false],
		["trigger guard", MeshFactory.torus(0.046, 0.011, 12, 5), false],
		["suit cuff", MeshFactory.torus(0.062, 0.018, 10, 5), false],
		["visor seal", MeshFactory.torus(0.118, 0.016, 16, 6), false],
		["antenna", MeshFactory.capsule(0.13, 0.011, 6), true],
		["helmet lamp", MeshFactory.tube(0.05, 0.032, 0.022, 8), false],
		["switch block", MeshFactory.beveled_box(Vector3(0.032, 0.032, 0.02), 0.008), true],
		["sight lens", MeshFactory.beveled_box(Vector3(0.026, 0.03, 0.004), 0.002), true],
		["glint", MeshFactory.sphere(0.021, 4, 7), true],
	]
	for entry in cases:
		var label: String = entry[0]
		var mesh: ArrayMesh = entry[1]
		var solid: bool = entry[2]
		if not check_eq(mesh.get_surface_count(), 1, "%s has a surface" % label):
			continue
		var vertices: PackedVector3Array = _surface_arrays(mesh)[Mesh.ARRAY_VERTEX]
		check(vertices.size() >= 12, "%s has real geometry (%d vertices)"
			% [label, vertices.size()])
		check(mesh.get_aabb().size.length() > 0.001, "%s has a real size" % label)
		_check_outward_winding(mesh, label, solid)


func test_new_primitives_are_the_size_they_claim() -> void:
	var ball := MeshFactory.sphere(0.4, 6, 11)
	_check_mesh_sane(ball, "sphere")
	_check_outward_winding(ball, "sphere")
	check_near(ball.get_aabb().size.y, 0.8, 0.02, "a sphere of radius r is 2r tall")

	# A capsule's `height` includes both caps, so a 1 m capsule is 1 m long -
	# the other convention makes every call site do arithmetic.
	var pill := MeshFactory.capsule(1.0, 0.2, 10, 3)
	_check_mesh_sane(pill, "capsule")
	_check_outward_winding(pill, "capsule")
	check_near(pill.get_aabb().size.y, 1.0, 0.02, "capsule height includes its caps")
	check_near(pill.get_aabb().size.x, 0.4, 0.03, "capsule is 2r wide")

	var pipe := MeshFactory.tube(0.6, 0.25, 0.15, 12)
	_check_mesh_sane(pipe, "tube")
	_check_outward_winding(pipe, "tube", false)
	check_near(pipe.get_aabb().size.y, 0.6, 0.02, "tube height")
	check_near(pipe.get_aabb().size.x, 0.5, 0.03, "tube outer diameter")

	var ring := MeshFactory.torus(0.5, 0.12, 16, 8)
	_check_mesh_sane(ring, "torus")
	_check_outward_winding(ring, "torus", false)
	check_near(ring.get_aabb().size.x, 1.24, 0.04, "torus spans 2*(major+minor)")
	check_near(ring.get_aabb().size.y, 0.24, 0.03, "torus is 2*minor tall")

	var ramp := MeshFactory.wedge(Vector3(1.0, 0.8, 1.2), 0.2)
	_check_mesh_sane(ramp, "wedge")
	_check_outward_winding(ramp, "wedge")
	check_near(ramp.get_aabb().size.y, 0.8, 0.02, "wedge height")
	check_near(ramp.get_aabb().size.z, 1.2, 0.02, "wedge depth")


func test_a_hollow_shape_really_is_hollow() -> void:
	# A tube whose inner wall was wound or normalled like the outer one looks
	# identical from outside and solid from the muzzle end, which defeats the
	# entire reason for having the shape.
	var pipe := MeshFactory.tube(0.6, 0.25, 0.15, 16)
	var arrays := _surface_arrays(pipe)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var inward_facing := 0
	for i in vertices.size():
		var radial := Vector2(vertices[i].x, vertices[i].z)
		if radial.length() > 0.19:
			continue
		var n := Vector2(normals[i].x, normals[i].z)
		if n.length() < 0.5:
			continue
		# On the bore, the surface normal must point back towards the axis.
		if n.normalized().dot(radial.normalized()) < -0.5:
			inward_facing += 1
	check(inward_facing >= 24,
		"the bore's normals point inwards, so you can see down it (%d found)"
		% inward_facing)
