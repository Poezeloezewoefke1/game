class_name ArmorBuilder
extends RefCounted
## Describes 3D armor pieces as coloured boxes attached to body parts. Armor is separate from the skin
## so any character can visibly wear leather / chainmail / iron / gold / diamond / netherite gear.
## Slots: helmet, chestplate, leggings, boots. Tiers: leather, chainmail, iron, gold, diamond, netherite.
## Set entries may carry an "_enchanted" suffix (e.g. "diamond_enchanted") to add the glint.

const TIER_COLORS := {
	"leather": Color(0.58, 0.36, 0.17),
	"chainmail": Color(0.55, 0.57, 0.62),
	"iron": Color(0.86, 0.86, 0.88),
	"gold": Color(0.97, 0.78, 0.22),
	"diamond": Color(0.33, 0.87, 0.85),
	"netherite": Color(0.30, 0.27, 0.29),
	"royal": Color(0.25, 0.42, 0.85),      # Parrot's Kingdom royal army livery (gameplay palette)
	"cinder": Color(0.62, 0.16, 0.08),     # Cindercrest livery (gameplay palette)
}

const TIER_ARMOR_POINTS := {
	"leather": 1, "chainmail": 2, "gold": 2, "iron": 3, "diamond": 4, "netherite": 5, "royal": 3, "cinder": 4,
}

static func parse_tier(tier_id: String) -> Dictionary:
	var glint := 0.0
	var base := tier_id
	if tier_id.ends_with("_enchanted"):
		glint = 1.0
		base = tier_id.trim_suffix("_enchanted")
	return {"base": base, "glint": glint, "color": TIER_COLORS.get(base, Color.MAGENTA)}

## Returns box descriptors: {min, size, color, part, glint}
## Pieces are built as SHELLS rather than solid boxes, so the character's face and skin stay readable
## while the gear tier is still obvious at a glance.
static func boxes_for_set(armor: Dictionary, slim: bool) -> Array:
	var out: Array = []
	var aw: float = 3.0 if slim else 4.0
	if armor.has("helmet"):
		var t := parse_tier(armor["helmet"])
		var h := MCGeometry.Part.HEAD
		# Open-faced helm: skull cap, back, cheek guards and a brow band. The face stays visible.
		out.append(_box(Vector3(-4, 30, -4), Vector3(8, 2, 8), 0.7, t, h))          # crown of the skull
		out.append(_box(Vector3(-4, 24, 3), Vector3(8, 6, 1), 0.7, t, h))           # back plate
		out.append(_box(Vector3(3, 24, -4), Vector3(1, 6, 8), 0.7, t, h))           # right cheek guard
		out.append(_box(Vector3(-4, 24, -4), Vector3(1, 6, 8), 0.7, t, h))          # left cheek guard
		out.append(_box(Vector3(-4, 29, -4), Vector3(8, 1.5, 1), 0.7, t, h))        # brow band
		out.append(_box(Vector3(-0.75, 26, -4.6), Vector3(1.5, 4, 0.6), 0.0, t, h)) # nasal bar
	if armor.has("chestplate"):
		var t := parse_tier(armor["chestplate"])
		out.append(_box(Vector3(-4, 13, -2), Vector3(8, 10, 4), 0.6, t, MCGeometry.Part.BODY))
		out.append(_box(Vector3(4, 20, -2), Vector3(aw, 4, 4), 0.7, t, MCGeometry.Part.RIGHT_ARM))
		out.append(_box(Vector3(-4 - aw, 20, -2), Vector3(aw, 4, 4), 0.7, t, MCGeometry.Part.LEFT_ARM))
	if armor.has("leggings"):
		var t := parse_tier(armor["leggings"])
		out.append(_box(Vector3(-4, 12, -2), Vector3(8, 3, 4), 0.85, t, MCGeometry.Part.BODY))
		out.append(_box(Vector3(0, 7, -2), Vector3(4, 5, 4), 0.5, t, MCGeometry.Part.RIGHT_LEG))
		out.append(_box(Vector3(-4, 7, -2), Vector3(4, 5, 4), 0.5, t, MCGeometry.Part.LEFT_LEG))
	if armor.has("boots"):
		var t := parse_tier(armor["boots"])
		out.append(_box(Vector3(0, 0, -2), Vector3(4, 3.5, 4), 0.75, t, MCGeometry.Part.RIGHT_LEG))
		out.append(_box(Vector3(-4, 0, -2), Vector3(4, 3.5, 4), 0.75, t, MCGeometry.Part.LEFT_LEG))
	if armor.has("crown"):
		var c := Color(0.98, 0.82, 0.25)
		out.append({"min": Vector3(-4.5, 31.5, -4.5), "size": Vector3(9, 2, 9), "color": c, "part": MCGeometry.Part.HEAD, "glint": 1.0})
		for i in 4:
			var x := -4.0 + i * 2.5
			out.append({"min": Vector3(x, 33.5, -4.5), "size": Vector3(1.2, 2, 1), "color": c, "part": MCGeometry.Part.HEAD, "glint": 1.0})
	if armor.has("cape"):
		var t := parse_tier(armor["cape"])
		out.append({"min": Vector3(-5, 8, 2.3), "size": Vector3(10, 16, 1), "color": t["color"], "part": MCGeometry.Part.BODY, "glint": 0.0})
	if armor.has("elytra"):
		var c := Color(0.35, 0.3, 0.45)
		out.append({"min": Vector3(1, 6, 2.3), "size": Vector3(7, 18, 1), "color": c, "part": MCGeometry.Part.BODY, "glint": 0.0})
		out.append({"min": Vector3(-8, 6, 2.3), "size": Vector3(7, 18, 1), "color": c, "part": MCGeometry.Part.BODY, "glint": 0.0})
	return out

static func _box(bmin: Vector3, size: Vector3, inflate: float, tier: Dictionary, part: int) -> Dictionary:
	return {
		"min": bmin - Vector3.ONE * inflate, "size": size + Vector3.ONE * (2.0 * inflate),
		"color": tier["color"], "part": part, "glint": tier["glint"],
	}

## Total armor points for a set, used by the damage formula.
static func armor_points(armor: Dictionary) -> int:
	var pts := 0
	for slot in ["helmet", "chestplate", "leggings", "boots"]:
		if armor.has(slot):
			var t := parse_tier(armor[slot])
			var base: int = TIER_ARMOR_POINTS.get(t["base"], 0)
			var weight := 1.0
			match slot:
				"chestplate": weight = 1.6
				"leggings": weight = 1.2
				_: weight = 0.6
			pts += int(round(base * weight)) + int(t["glint"])
	return pts

## Builds a mesh for a single armor piece relative to the given part's pivot (node-based characters).
static func build_piece_mesh(boxes: Array, pivot_px: Vector3) -> ArrayMesh:
	var b := MCMeshBuilder.new()
	b.tex_size = Vector2(16, 16)
	b.local_origin = pivot_px
	for box in boxes:
		b.add_color_box(box["min"], box["size"], box["color"], box["part"], pivot_px, box.get("glint", 0.0))
	return b.commit()
