class_name MCMeshBuilder
extends RefCounted
## Accumulates textured boxes into a single ArrayMesh surface with the custom vertex attributes
## used by mc_character shaders:
##   CUSTOM0 = (part_id, use_vertex_color, enchant_glint, 0)
##   CUSTOM1 = (pivot.x, pivot.y, pivot.z, 0)   -- pivot in world units, for GPU limb animation
## Winding: Godot treats clockwise (seen from outside) as front faces.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var colors := PackedColorArray()
var custom0 := PackedFloat32Array()
var custom1 := PackedFloat32Array()
var indices := PackedInt32Array()

var tex_size := Vector2(64, 64)
var local_origin := Vector3.ZERO      # subtracted from every vertex (pixels)
var xform := Transform3D.IDENTITY     # applied after origin shift (pixels space)
var flip_winding := false

func reset() -> void:
	verts = PackedVector3Array(); normals = PackedVector3Array(); uvs = PackedVector2Array()
	colors = PackedColorArray(); custom0 = PackedFloat32Array(); custom1 = PackedFloat32Array()
	indices = PackedInt32Array()

func vertex_count() -> int:
	return verts.size()

## Adds a skin-textured box. bmin/size in pixels. uv/uv_dims describe the net; mirror flips left/right.
func add_skin_box(bmin: Vector3, size: Vector3, uv: Vector2i, uv_dims: Vector3i, mirror: bool,
		inflate: float, part_id: int, pivot_px: Vector3, glint: float = 0.0) -> void:
	var rects := MCGeometry.face_rects(uv, uv_dims, mirror)
	_add_box(bmin - Vector3.ONE * inflate, size + Vector3.ONE * (2.0 * inflate), rects, mirror,
		Color.WHITE, part_id, 0.0, glint, pivot_px, false)

## Adds a solid-coloured box (armor, weapons). UVs tile the shared armor pattern texture.
func add_color_box(bmin: Vector3, size: Vector3, color: Color, part_id: int, pivot_px: Vector3,
		glint: float = 0.0, pattern_scale: float = 8.0) -> void:
	var rects := {}
	for face in ["right", "left", "front", "back", "top", "bottom"]:
		var fw: float
		var fh: float
		match face:
			"right", "left":
				fw = size.z; fh = size.y
			"front", "back":
				fw = size.x; fh = size.y
			_:
				fw = size.x; fh = size.z
		rects[face] = Rect2(0, 0, fw / pattern_scale * tex_size.x, fh / pattern_scale * tex_size.y)
	_add_box(bmin, size, rects, false, color, part_id, 1.0, glint, pivot_px, true)

func _add_box(bmin: Vector3, size: Vector3, rects: Dictionary, mirror: bool, color: Color,
		part_id: int, use_color: float, glint: float, pivot_px: Vector3, pattern: bool) -> void:
	var x0 := bmin.x
	var y0 := bmin.y
	var z0 := bmin.z
	var x1 := bmin.x + size.x
	var y1 := bmin.y + size.y
	var z1 := bmin.z + size.z
	# Faces as (TL, TR, BR, BL) seen from outside, plus UV corner order flag.
	_face(rects["front"], mirror, Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(0, 0, -1), false, color, part_id, use_color, glint, pivot_px, pattern)
	_face(rects["back"], mirror, Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3(0, 0, 1), false, color, part_id, use_color, glint, pivot_px, pattern)
	_face(rects["right"], mirror, Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(1, 0, 0), false, color, part_id, use_color, glint, pivot_px, pattern)
	_face(rects["left"], mirror, Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3(x0, y0, z0), Vector3(-1, 0, 0), false, color, part_id, use_color, glint, pivot_px, pattern)
	_face(rects["top"], mirror, Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(0, 1, 0), false, color, part_id, use_color, glint, pivot_px, pattern)
	_face(rects["bottom"], mirror, Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(0, -1, 0), true, color, part_id, use_color, glint, pivot_px, pattern)

func _face(rect: Rect2, mirror: bool, tl: Vector3, tr: Vector3, br: Vector3, bl: Vector3, normal: Vector3,
		flip_v: bool, color: Color, part_id: int, use_color: float, glint: float, pivot_px: Vector3, pattern: bool) -> void:
	var u1 := rect.position.x / tex_size.x
	var u2 := (rect.position.x + rect.size.x) / tex_size.x
	var v1 := rect.position.y / tex_size.y
	var v2 := (rect.position.y + rect.size.y) / tex_size.y
	if pattern:
		u1 = 0.0; u2 = rect.size.x / tex_size.x; v1 = 0.0; v2 = rect.size.y / tex_size.y
	if mirror and not pattern:
		var t := u1
		u1 = u2
		u2 = t
	var uv_tl := Vector2(u1, v1)
	var uv_tr := Vector2(u2, v1)
	var uv_br := Vector2(u2, v2)
	var uv_bl := Vector2(u1, v2)
	if flip_v:
		uv_tl = Vector2(u1, v2); uv_tr = Vector2(u2, v2); uv_br = Vector2(u2, v1); uv_bl = Vector2(u1, v1)
	var base := verts.size()
	var n := (xform.basis * normal).normalized()
	var pivot := (xform * (pivot_px - local_origin)) * MCGeometry.PX
	for i in 4:
		var p: Vector3 = [tl, tr, br, bl][i]
		var uvp: Vector2 = [uv_tl, uv_tr, uv_br, uv_bl][i]
		verts.push_back((xform * (p - local_origin)) * MCGeometry.PX)
		normals.push_back(n)
		uvs.push_back(uvp)
		colors.push_back(color)
		custom0.append_array(PackedFloat32Array([float(part_id), use_color, glint, 0.0]))
		custom1.append_array(PackedFloat32Array([pivot.x, pivot.y, pivot.z, 0.0]))
	if flip_winding:
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	else:
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_CUSTOM1] = custom1
	arrays[Mesh.ARRAY_INDEX] = indices
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh

## Builds one body part (inner + outer layer) with vertices relative to the part's pivot.
static func build_part_mesh(skin: SkinData, def: Dictionary) -> ArrayMesh:
	var b := MCMeshBuilder.new()
	b.tex_size = skin.texture_size()
	b.local_origin = def["pivot"]
	var size := Vector3(def["size"])
	b.add_skin_box(def["min"], size, def["uv"], def["size"], def["mirror"], 0.0, def["part"], def["pivot"])
	if def["uv_outer"] != null:
		b.add_skin_box(def["min"], size, def["uv_outer"], def["size"], def["mirror"], def["inflate_outer"], def["part"], def["pivot"])
	return b.commit()

## Builds a full character (all parts + armor + held item) as ONE mesh in character space, for MultiMesh rendering.
## armor: Dictionary slot -> tier id (see ArmorBuilder); held: weapon id (see WeaponBuilder)
static func build_merged_character(skin: SkinData, armor: Dictionary = {}, held: String = "", extras: Array = []) -> ArrayMesh:
	var b := MCMeshBuilder.new()
	b.tex_size = skin.texture_size()
	var defs := MCGeometry.part_defs(skin.slim, skin.legacy)
	for def in defs:
		var size := Vector3(def["size"])
		b.add_skin_box(def["min"], size, def["uv"], def["size"], def["mirror"], 0.0, def["part"], def["pivot"])
		if def["uv_outer"] != null:
			b.add_skin_box(def["min"], size, def["uv_outer"], def["size"], def["mirror"], def["inflate_outer"], def["part"], def["pivot"])
	# Pattern-textured boxes use the armor texture size (16x16) for tiling; store skin size separately.
	var skin_tex := b.tex_size
	b.tex_size = Vector2(16, 16)
	for box in ArmorBuilder.boxes_for_set(armor, skin.slim):
		var pivot: Vector3 = MCGeometry.part_def(defs, box["part"])["pivot"]
		b.add_color_box(box["min"], box["size"], box["color"], box["part"], pivot, box.get("glint", 0.0))
	if held != "":
		var arm_def := MCGeometry.part_def(defs, MCGeometry.Part.RIGHT_ARM)
		var pivot: Vector3 = arm_def["pivot"]
		var hand := pivot + MCGeometry.held_item_offset(skin.slim)
		var item_xform := Transform3D(MCGeometry.held_item_basis(), hand)
		for box in WeaponBuilder.boxes_for(held):
			var bmin: Vector3 = box["min"]
			var bsize: Vector3 = box["size"]
			b.xform = item_xform
			b.local_origin = Vector3.ZERO
			# pivot must be expressed in the same (untransformed) frame: pass inverse-transformed pivot
			var pivot_local := item_xform.affine_inverse() * pivot
			b.add_color_box(bmin, bsize, box["color"], MCGeometry.Part.HELD, pivot_local, box.get("glint", 0.0))
		b.xform = Transform3D.IDENTITY
	for extra in extras:
		var part: int = extra.get("part", MCGeometry.Part.BODY)
		var pivot: Vector3 = MCGeometry.part_def(defs, part)["pivot"]
		b.add_color_box(extra["min"], extra["size"], extra["color"], part, pivot, extra.get("glint", 0.0))
	b.tex_size = skin_tex
	return b.commit()
