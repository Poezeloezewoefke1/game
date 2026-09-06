class_name MCGeometry
extends RefCounted
## Canonical Minecraft humanoid box layout. All numbers are in skin pixels (16 px = 1 world unit).
## Character faces -Z. The character's RIGHT side is +X (so it appears on the viewer's left when facing it).

const PX := 1.0 / 16.0

enum Part { HEAD = 0, BODY = 1, RIGHT_ARM = 2, LEFT_ARM = 3, RIGHT_LEG = 4, LEFT_LEG = 5, HELD = 6, EXTRA = 7 }

const PART_NAMES := ["Head", "Body", "RightArm", "LeftArm", "RightLeg", "LeftLeg", "Held", "Extra"]

## Returns the six body part definitions for the given skin variant.
## Each entry: name, part, size (w,h,d), min (box corner), pivot, uv, uv_outer (or null), inflate_outer, mirror
static func part_defs(slim: bool, legacy: bool) -> Array:
	var aw: int = 3 if slim else 4
	var defs: Array = []
	defs.append({
		"name": "Head", "part": Part.HEAD, "size": Vector3i(8, 8, 8),
		"min": Vector3(-4, 24, -4), "pivot": Vector3(0, 24, 0),
		"uv": Vector2i(0, 0), "uv_outer": Vector2i(32, 0), "inflate_outer": 0.5, "mirror": false,
	})
	defs.append({
		"name": "Body", "part": Part.BODY, "size": Vector3i(8, 12, 4),
		"min": Vector3(-4, 12, -2), "pivot": Vector3(0, 24, 0),
		"uv": Vector2i(16, 16), "uv_outer": null if legacy else Vector2i(16, 32), "inflate_outer": 0.25, "mirror": false,
	})
	defs.append({
		"name": "RightArm", "part": Part.RIGHT_ARM, "size": Vector3i(aw, 12, 4),
		"min": Vector3(4, 12, -2), "pivot": Vector3(4 + aw * 0.5, 22, 0),
		"uv": Vector2i(40, 16), "uv_outer": null if legacy else Vector2i(40, 32), "inflate_outer": 0.25, "mirror": false,
	})
	defs.append({
		"name": "LeftArm", "part": Part.LEFT_ARM, "size": Vector3i(aw, 12, 4),
		"min": Vector3(-4 - aw, 12, -2), "pivot": Vector3(-(4 + aw * 0.5), 22, 0),
		"uv": Vector2i(40, 16) if legacy else Vector2i(32, 48),
		"uv_outer": null if legacy else Vector2i(48, 48), "inflate_outer": 0.25, "mirror": legacy,
	})
	defs.append({
		"name": "RightLeg", "part": Part.RIGHT_LEG, "size": Vector3i(4, 12, 4),
		"min": Vector3(0, 0, -2), "pivot": Vector3(2, 12, 0),
		"uv": Vector2i(0, 16), "uv_outer": null if legacy else Vector2i(0, 32), "inflate_outer": 0.25, "mirror": false,
	})
	defs.append({
		"name": "LeftLeg", "part": Part.LEFT_LEG, "size": Vector3i(4, 12, 4),
		"min": Vector3(-4, 0, -2), "pivot": Vector3(-2, 12, 0),
		"uv": Vector2i(0, 16) if legacy else Vector2i(16, 48),
		"uv_outer": null if legacy else Vector2i(0, 48), "inflate_outer": 0.25, "mirror": legacy,
	})
	return defs

static func part_def(defs: Array, part: int) -> Dictionary:
	for d in defs:
		if d["part"] == part:
			return d
	return {}

## UV rectangles (x1, y1, x2, y2) in pixel space for each face of a box in the standard net layout.
## Keys: right(+X), front(-Z), left(-X), back(+Z), top(+Y), bottom(-Y)
static func face_rects(uv: Vector2i, dims: Vector3i, mirror: bool) -> Dictionary:
	var u := uv.x
	var v := uv.y
	var w := dims.x
	var h := dims.y
	var d := dims.z
	var rects := {
		"right": Rect2(u, v + d, d, h),
		"front": Rect2(u + d, v + d, w, h),
		"left": Rect2(u + d + w, v + d, d, h),
		"back": Rect2(u + 2 * d + w, v + d, w, h),
		"top": Rect2(u + d, v, w, d),
		"bottom": Rect2(u + d + w, v, w, d),
	}
	if mirror:
		var r = rects["right"]
		rects["right"] = rects["left"]
		rects["left"] = r
	return rects

## Held item socket (in pixels relative to the right-arm pivot) and default rotation.
static func held_item_offset(slim: bool) -> Vector3:
	return Vector3(0.0, -10.0, -1.0) if not slim else Vector3(0.0, -10.0, -1.0)

static func held_item_basis() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(-75.0), 0.0, 0.0))
