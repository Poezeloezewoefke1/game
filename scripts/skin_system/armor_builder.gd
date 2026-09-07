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

# ================================================================================================
# Real armour layers (Minecraft resource pack)
# ================================================================================================
#
# The shell boxes above are the fallback. When a resource pack is installed, armour is drawn the way
# Minecraft draws it: a copy of the humanoid model inflated slightly and textured by the pack's
# equipment layers. Those textures use the 64x32 legacy skin net, and the leg/arm regions are mostly
# transparent except where the piece actually covers -- which is why boots and leggings can share the
# leg model without either drawing a whole armoured leg.
#
# Layer 1 (humanoid/*.png) is helmet, chestplate and boots; layer 2 (humanoid_leggings/*.png) is
# leggings. Vanilla inflates them by 1.0 and 0.5 pixels respectively, which is also what keeps a
# chestplate and a pair of leggings from z-fighting on the torso.

const LAYER_1_INFLATE := 1.0
const LAYER_2_INFLATE := 0.5

## slot -> [layer, [part ids]]
const SLOT_COVERAGE := {
	"helmet": [1, [MCGeometry.Part.HEAD]],
	"chestplate": [1, [MCGeometry.Part.BODY, MCGeometry.Part.RIGHT_ARM, MCGeometry.Part.LEFT_ARM]],
	"leggings": [2, [MCGeometry.Part.BODY, MCGeometry.Part.RIGHT_LEG, MCGeometry.Part.LEFT_LEG]],
	"boots": [1, [MCGeometry.Part.RIGHT_LEG, MCGeometry.Part.LEFT_LEG]],
}

## True when real armour layers can be drawn for this set — i.e. a pack is installed and it has a
## texture for at least one equipped tier.
static func layers_available(armor: Dictionary) -> bool:
	if not ResourcePack.available():
		return false
	for slot in armor.keys():
		if not SLOT_COVERAGE.has(slot):
			continue
		var t := parse_tier(String(armor[slot]))
		if ResourcePack.armor_layer(String(t["base"]), int(SLOT_COVERAGE[slot][0])) != null:
			return true
	return false

## The slots of `armor` that real layers cannot draw: anything outside the four equipment slots
## (capes, elytra, crowns) and any tier the pack has no texture for (this project's invented royal and
## cinder liveries). These keep the shell-box treatment so nothing vanishes when a pack is installed.
static func slots_without_layers(armor: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for slot in armor.keys():
		var s := String(slot)
		if not SLOT_COVERAGE.has(s):
			out[s] = armor[slot]
			continue
		var t := parse_tier(String(armor[slot]))
		if ResourcePack.armor_layer(String(t["base"]), int(SLOT_COVERAGE[s][0])) == null:
			out[s] = armor[slot]
	return out

## Describes the armour of `armor` as layer pieces, grouped so each group is one draw with one
## texture. Returns [{material, layer, glint, parts: [{part, min, size, uv, uv_dims, mirror, pivot}]}].
## The armour model is always the standard 4-wide-arm humanoid, as in vanilla, even over a slim skin.
static func layer_groups(armor: Dictionary) -> Array:
	var defs := MCGeometry.part_defs(false, true)      # classic body, legacy net == the armour net
	var groups: Dictionary = {}                        # "material:layer" -> group
	for slot in ["chestplate", "leggings", "boots", "helmet"]:
		if not armor.has(slot):
			continue
		var t := parse_tier(String(armor[slot]))
		var material := String(t["base"])
		var layer := int(SLOT_COVERAGE[slot][0])
		if ResourcePack.armor_layer(material, layer) == null:
			continue
		var key := "%s:%d" % [material, layer]
		if not groups.has(key):
			groups[key] = {"material": material, "layer": layer, "glint": float(t["glint"]), "parts": []}
		elif float(t["glint"]) > 0.0:
			groups[key]["glint"] = 1.0
		var seen: Dictionary = {}
		for p in groups[key]["parts"]:
			seen[int(p["part"])] = true
		for part in SLOT_COVERAGE[slot][1]:
			if seen.has(int(part)):
				continue                               # e.g. boots and leggings both list the legs
			var def := MCGeometry.part_def(defs, part)
			groups[key]["parts"].append({
				"part": part, "min": def["min"], "size": Vector3(def["size"]),
				"uv": def["uv"], "uv_dims": def["size"], "mirror": def["mirror"], "pivot": def["pivot"],
			})
	return groups.values()

## One armour layer group as a mesh relative to a body part's pivot (node-based characters).
static func build_layer_piece_mesh(parts: Array, layer: int, pivot_px: Vector3) -> ArrayMesh:
	var b := MCMeshBuilder.new()
	b.tex_size = Vector2(64, 32)
	b.local_origin = pivot_px
	var inflate := LAYER_1_INFLATE if layer == 1 else LAYER_2_INFLATE
	for p in parts:
		b.add_skin_box(p["min"], p["size"], p["uv"], p["uv_dims"], p["mirror"], inflate,
			int(p["part"]), p["pivot"])
	return b.commit()

## Every armour layer group of a set merged into one mesh in character space (MultiMesh rendering).
## One mesh per group, because each group needs its own texture.
static func build_layer_merged_mesh(parts: Array, layer: int) -> ArrayMesh:
	var b := MCMeshBuilder.new()
	b.tex_size = Vector2(64, 32)
	var inflate := LAYER_1_INFLATE if layer == 1 else LAYER_2_INFLATE
	for p in parts:
		b.add_skin_box(p["min"], p["size"], p["uv"], p["uv_dims"], p["mirror"], inflate,
			int(p["part"]), p["pivot"])
	return b.commit()
