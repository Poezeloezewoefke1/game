class_name WeaponBuilder
extends RefCounted
## Procedural blocky item models built from coloured boxes. Item space: handle base at origin, item extends +Y.
## Units are skin pixels. The character system places the item in the right hand and tilts it forward.

const WOOD := Color(0.45, 0.30, 0.15)
const DARK := Color(0.16, 0.15, 0.17)
const STRING := Color(0.9, 0.9, 0.85)

static func blade_color(material: String) -> Color:
	match material:
		"wood": return Color(0.55, 0.38, 0.2)
		"stone": return Color(0.5, 0.5, 0.52)
		"iron": return Color(0.88, 0.88, 0.9)
		"gold": return Color(0.98, 0.8, 0.25)
		"diamond": return Color(0.4, 0.9, 0.88)
		"netherite": return Color(0.3, 0.27, 0.3)
		_: return Color(0.7, 0.7, 0.7)

## Returns box descriptors {min, size, color, glint}
static func boxes_for(weapon_id: String) -> Array:
	var glint := 0.0
	var wid := weapon_id
	if wid.ends_with("_enchanted"):
		glint = 1.0
		wid = wid.trim_suffix("_enchanted")
	var parts := wid.split("_")
	var kind := parts[parts.size() - 1]
	var material := parts[0] if parts.size() > 1 else "iron"
	var out: Array = []
	match kind:
		"sword":
			out.append(_b(Vector3(-0.75, 0, -0.75), Vector3(1.5, 5, 1.5), WOOD))
			out.append(_b(Vector3(-2.5, 5, -0.75), Vector3(5, 1.5, 1.5), DARK))
			out.append(_b(Vector3(-1, 6.5, -0.5), Vector3(2, 12, 1), blade_color(material), glint))
			out.append(_b(Vector3(-0.5, 18.5, -0.5), Vector3(1, 1.5, 1), blade_color(material), glint))
		"axe":
			out.append(_b(Vector3(-0.75, 0, -0.75), Vector3(1.5, 14, 1.5), WOOD))
			out.append(_b(Vector3(-1, 10, -0.75), Vector3(6, 6, 1.5), blade_color(material), glint))
			out.append(_b(Vector3(-1, 9, -0.75), Vector3(2.5, 8, 1.5), blade_color(material), glint))
		"mace":
			out.append(_b(Vector3(-0.75, 0, -0.75), Vector3(1.5, 10, 1.5), WOOD))
			out.append(_b(Vector3(-2.5, 10, -2.5), Vector3(5, 5, 5), Color(0.24, 0.22, 0.25), glint))
			out.append(_b(Vector3(-1.5, 15, -1.5), Vector3(3, 1.5, 3), Color(0.24, 0.22, 0.25), glint))
			out.append(_b(Vector3(-1.5, 8.5, -1.5), Vector3(3, 1.5, 3), Color(0.24, 0.22, 0.25), glint))
			for i in 4:
				var a := i * PI * 0.5
				var off := Vector3(cos(a) * 3.0, 12.5, sin(a) * 3.0)
				out.append(_b(off - Vector3(0.5, 0.75, 0.5), Vector3(1, 1.5, 1), Color(0.5, 0.48, 0.5), glint))
		"bow":
			out.append(_b(Vector3(-0.6, 0, -0.6), Vector3(1.2, 6, 1.2), WOOD))
			out.append(_b(Vector3(-0.6, 6, -0.6), Vector3(1.2, 10, 1.2), WOOD))
			out.append(_b(Vector3(-0.6, 15, -3.5), Vector3(1.2, 1.2, 3.5), WOOD))
			out.append(_b(Vector3(-0.6, 0, -3.5), Vector3(1.2, 1.2, 3.5), WOOD))
			out.append(_b(Vector3(-0.2, 1, -3.4), Vector3(0.4, 14.5, 0.4), STRING))
		"crossbow":
			out.append(_b(Vector3(-1, 0, -1), Vector3(2, 12, 2), WOOD))
			out.append(_b(Vector3(-5, 9, -0.5), Vector3(10, 1.5, 1.5), Color(0.3, 0.3, 0.35)))
			out.append(_b(Vector3(-5, 8.5, -0.2), Vector3(10, 0.4, 0.4), STRING))
		"trident":
			out.append(_b(Vector3(-0.6, 0, -0.6), Vector3(1.2, 16, 1.2), Color(0.35, 0.65, 0.6), glint))
			for i in 3:
				var x := -2.0 + i * 2.0
				out.append(_b(Vector3(x - 0.5, 16, -0.5), Vector3(1, 4, 1), Color(0.45, 0.8, 0.75), glint))
			out.append(_b(Vector3(-2.5, 15.5, -0.5), Vector3(5, 1, 1), Color(0.45, 0.8, 0.75), glint))
		"shield":
			out.append(_b(Vector3(-4, 0, -0.5), Vector3(8, 12, 1), Color(0.35, 0.25, 0.15)))
			out.append(_b(Vector3(-3, 1, -0.9), Vector3(6, 10, 0.5), Color(0.25, 0.42, 0.85)))
		"tnt":
			out.append(_b(Vector3(-4, 0, -4), Vector3(8, 8, 8), Color(0.85, 0.15, 0.1)))
			out.append(_b(Vector3(-4.2, 3, -4.2), Vector3(8.4, 2, 8.4), Color(0.95, 0.95, 0.9)))
			out.append(_b(Vector3(-0.4, 8, -0.4), Vector3(0.8, 2.5, 0.8), STRING))
		"potion":
			out.append(_b(Vector3(-1.75, 0, -1.75), Vector3(3.5, 4, 3.5), Color(0.45, 0.6, 0.95, 1.0), glint))
			out.append(_b(Vector3(-0.9, 4, -0.9), Vector3(1.8, 2.5, 1.8), Color(0.75, 0.85, 0.95)))
			out.append(_b(Vector3(-1.1, 6.5, -1.1), Vector3(2.2, 1, 2.2), Color(0.55, 0.38, 0.2)))
		"totem":
			out.append(_b(Vector3(-2, 0, -1), Vector3(4, 6, 2), Color(0.95, 0.78, 0.2), 1.0))
			out.append(_b(Vector3(-2, 6, -2), Vector3(4, 4, 4), Color(0.4, 0.75, 0.35)))
			out.append(_b(Vector3(-4.5, 4, -1), Vector3(2.5, 1.5, 2), Color(0.95, 0.78, 0.2)))
			out.append(_b(Vector3(2, 4, -1), Vector3(2.5, 1.5, 2), Color(0.95, 0.78, 0.2)))
		"banner":
			var cloth := Color(0.25, 0.42, 0.85) if material != "cinder" else Color(0.62, 0.16, 0.08)
			out.append(_b(Vector3(-0.6, 0, -0.6), Vector3(1.2, 26, 1.2), WOOD))
			out.append(_b(Vector3(-4, 12, -0.3), Vector3(8, 13, 0.6), cloth))
			out.append(_b(Vector3(-4.5, 24.5, -0.8), Vector3(9, 1.2, 1.6), Color(0.85, 0.7, 0.3)))
		"spear":
			out.append(_b(Vector3(-0.6, 0, -0.6), Vector3(1.2, 20, 1.2), WOOD))
			out.append(_b(Vector3(-1, 20, -0.6), Vector3(2, 5, 1.2), blade_color(material), glint))
		"book":
			out.append(_b(Vector3(-3, 0, -2), Vector3(6, 1, 4), Color(0.6, 0.35, 0.2)))
			out.append(_b(Vector3(-2.5, 1, -1.5), Vector3(5, 0.6, 3), Color(0.95, 0.92, 0.85)))
		"pearl":
			out.append(_b(Vector3(-1.5, 0, -1.5), Vector3(3, 3, 3), Color(0.1, 0.35, 0.3), 1.0))
		"firework":
			out.append(_b(Vector3(-0.8, 0, -0.8), Vector3(1.6, 6, 1.6), Color(0.85, 0.2, 0.2)))
			out.append(_b(Vector3(-0.3, 6, -0.3), Vector3(0.6, 2, 0.6), STRING))
		"wand", "stick":
			out.append(_b(Vector3(-0.6, 0, -0.6), Vector3(1.2, 10, 1.2), WOOD))
		_:
			out.append(_b(Vector3(-0.75, 0, -0.75), Vector3(1.5, 10, 1.5), WOOD))
	return out

static func _b(bmin: Vector3, size: Vector3, color: Color, glint: float = 0.0) -> Dictionary:
	return {"min": bmin, "size": size, "color": color, "glint": glint}

## Mesh in item space (for node-based characters and UI previews).
static func build_mesh(weapon_id: String) -> ArrayMesh:
	var b := MCMeshBuilder.new()
	b.tex_size = Vector2(16, 16)
	for box in boxes_for(weapon_id):
		b.add_color_box(box["min"], box["size"], box["color"], MCGeometry.Part.HELD, Vector3.ZERO, box.get("glint", 0.0))
	return b.commit()
