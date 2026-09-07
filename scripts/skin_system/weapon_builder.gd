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

# ================================================================================================
# Real Minecraft items
# ================================================================================================
#
# The coloured boxes above are the fallback. When a resource pack is installed a held item is built
# the way Minecraft builds one, which is three different things depending on the item:
#
#   * Most items are a flat 16x16 inventory sprite extruded into a slab one sixteenth of a block
#     thick. Front and back faces carry the whole sprite, and a side quad is emitted wherever an
#     opaque pixel borders a transparent one -- that stepped rim is what makes a sword read as a
#     solid object instead of a cardboard cutout.
#   * Shields and banners are not sprites at all: the game draws them from a small box model with
#     its own entity texture, exactly like a body part.
#   * TNT is a block, so it is a cube wearing the block's six faces.
#
# Vanilla also poses the two sprite classes differently, and that difference is very visible:
# tools use the `handheld` display transform, which rolls the sprite so its bottom-left-to-top-right
# diagonal points out of the fist, while everything else uses `generated`, which stands the sprite
# upright. Both are reproduced below.

## Item thickness in skin pixels, matching vanilla's 1/16 of a block.
const ITEM_DEPTH_PX := 1.0
## Skin pixels per sprite pixel. A sword sprite is 16 across but ~22.6 along its diagonal, so at this
## scale the blade comes out about 19px long -- the same reach the box models had.
const ITEM_SCALE := 0.85
## Alpha at or below this counts as empty when tracing the sprite's silhouette.
const ALPHA_CUT := 0.5

## Sprite items: this project's weapon id -> the pack's item texture and its vanilla pose.
## `handheld` is vanilla's tool pose (rolled onto the sprite diagonal); false is `generated`.
const SPRITE_ITEMS := {
	"wood_sword": {"tex": "wooden_sword", "handheld": true},
	"stone_sword": {"tex": "stone_sword", "handheld": true},
	"iron_sword": {"tex": "iron_sword", "handheld": true},
	"gold_sword": {"tex": "golden_sword", "handheld": true},
	"diamond_sword": {"tex": "diamond_sword", "handheld": true},
	"netherite_sword": {"tex": "netherite_sword", "handheld": true},
	"iron_axe": {"tex": "iron_axe", "handheld": true},
	"diamond_axe": {"tex": "diamond_axe", "handheld": true},
	"netherite_axe": {"tex": "netherite_axe", "handheld": true},
	"mace": {"tex": "mace", "handheld": true},
	"netherite_mace": {"tex": "mace", "handheld": true},
	"bow": {"tex": "bow", "handheld": true},
	# Vanilla's unloaded crossbow icon is `crossbow_standby`; plain "crossbow" is not a texture.
	"crossbow": {"tex": "crossbow_standby", "handheld": true},
	"trident": {"tex": "trident", "handheld": true},
	"iron_spear": {"tex": "trident", "handheld": true},
	"stick": {"tex": "stick", "handheld": true},
	"wand": {"tex": "blaze_rod", "handheld": true},
	"potion": {"tex": "potion", "handheld": false},
	"totem": {"tex": "totem_of_undying", "handheld": false},
	"pearl": {"tex": "ender_pearl", "handheld": false},
	"book": {"tex": "enchanted_book", "handheld": false},
	"firework": {"tex": "firework_rocket", "handheld": false},
}

## Vanilla BannerModel at two fifths scale: at full size the flag is two and a half blocks tall and
## dwarfs the character carrying it. Only the geometry shrinks -- the UVs stay on the model's real net
## coordinates, so the cloth, pole and crossbar still take the right parts of the banner sheet.
## Like the shield's, the boxes straddle y=0: these are gripped in the middle of the pole, not at its foot.
const BANNER_BOXES := [
	{"min": Vector3(-4, -6, -0.2), "size": Vector3(8, 16, 0.4),
		"uv": Vector2i(0, 0), "uv_dims": Vector3i(20, 40, 1)},
	{"min": Vector3(-0.4, -9, -0.4), "size": Vector3(0.8, 19, 0.8),
		"uv": Vector2i(44, 0), "uv_dims": Vector3i(2, 42, 2)},
	{"min": Vector3(-4, 10, -0.4), "size": Vector3(8, 0.8, 0.8),
		"uv": Vector2i(0, 42), "uv_dims": Vector3i(20, 2, 2)},
]

## Vanilla dye colours; banner_base.png is the undyed white cloth the game multiplies by them.
const DYE_WHITE := Color(0.949, 0.949, 0.949)
const DYE_BLUE := Color(0.235, 0.267, 0.667)
const DYE_RED := Color(0.698, 0.118, 0.118)

## Box-model items: drawn from an entity texture with a real box net, not from a sprite.
## `upright` cancels the hand's forward tilt -- a shield or a banner is carried standing up, not
## levelled at the enemy -- and `rot` is a further lean applied on top of that.
const BOX_ITEMS := {
	# Vanilla ShieldModel: plate 12x22x1 at uv (0,0), handle 2x6x6 at uv (26,0), on a 64x64 sheet.
	"shield": {
		"texture": "entity/shield/shield_base_nopattern", "tex_size": Vector2(64, 64),
		"boxes": [
			{"min": Vector3(-6, -11, -2), "size": Vector3(12, 22, 1),
				"uv": Vector2i(0, 0), "uv_dims": Vector3i(12, 22, 1)},
			{"min": Vector3(-1, -3, -1), "size": Vector3(2, 6, 6),
				"uv": Vector2i(26, 0), "uv_dims": Vector3i(2, 6, 6)},
		],
		# Tipped back a little so the board camera sees the face of the plate, not its top edge.
		"upright": true, "rot": Vector3(-20, 0, 0),
	},
	"banner": {"texture": "entity/banner/banner_base", "tex_size": Vector2(64, 64),
		"boxes": BANNER_BOXES, "tint": DYE_WHITE, "upright": true, "rot": Vector3(-12, 0, 0)},
	"royal_banner": {"texture": "entity/banner/banner_base", "tex_size": Vector2(64, 64),
		"boxes": BANNER_BOXES, "tint": DYE_BLUE, "upright": true, "rot": Vector3(-12, 0, 0)},
	"cinder_banner": {"texture": "entity/banner/banner_base", "tex_size": Vector2(64, 64),
		"boxes": BANNER_BOXES, "tint": DYE_RED, "upright": true, "rot": Vector3(-12, 0, 0)},
}

## Block items: a cube wearing the block's faces. The net is composited on demand.
const CUBE_ITEMS := {
	"tnt": {"side": "tnt_side", "top": "tnt_top", "bottom": "tnt_bottom", "size": 8.0},
}

static var _image_cache: Dictionary = {}

# ------------------------------------------------------------------------------------------------
# Queries
# ------------------------------------------------------------------------------------------------

## Splits a weapon id into its base id and whether it carries the enchantment glint.
static func split_glint(weapon_id: String) -> Dictionary:
	if weapon_id.ends_with("_enchanted"):
		return {"id": weapon_id.trim_suffix("_enchanted"), "glint": 1.0}
	return {"id": weapon_id, "glint": 0.0}

## True when the installed pack can draw this weapon from real Minecraft art.
static func has_real_item(weapon_id: String) -> bool:
	return real_item_image(weapon_id) != null

## The texture a real item is drawn with: the composited sprite, entity sheet or cube net.
## Null when there is no pack, or no entry for this weapon. Cached, because compositing is not free.
static func real_item_image(weapon_id: String) -> Image:
	var id: String = split_glint(weapon_id)["id"]
	if _image_cache.has(id):
		return _image_cache[id]
	var img: Image = null
	if SPRITE_ITEMS.has(id):
		img = ResourcePack.item_image(String(SPRITE_ITEMS[id]["tex"]))
	elif BOX_ITEMS.has(id):
		var entry: Dictionary = BOX_ITEMS[id]
		img = ResourcePack.raw_image(String(entry["texture"]))
		if img != null and entry.has("tint"):
			img = img.duplicate()
			_tint(img, entry["tint"])
	elif CUBE_ITEMS.has(id):
		img = _cube_net(CUBE_ITEMS[id])
	_image_cache[id] = img
	return img

## Forgets the composited item textures. Only needed when a pack is swapped at runtime.
static func reset_cache() -> void:
	_image_cache.clear()

# ------------------------------------------------------------------------------------------------
# Mesh construction
# ------------------------------------------------------------------------------------------------

## Builds a real item's mesh. `xform` places the item's grip inside a larger merged character and
## `pivot_px` is the limb pivot that item must swing around, both in character pixel space; leave
## them at their defaults for a standalone mesh parented to the hand. Null when there is no art.
static func build_real_mesh(weapon_id: String, xform: Transform3D = Transform3D.IDENTITY,
		pivot_px: Vector3 = Vector3.ZERO, part_id: int = MCGeometry.Part.HELD) -> ArrayMesh:
	var img := real_item_image(weapon_id)
	if img == null:
		return null
	var split := split_glint(weapon_id)
	var id: String = split["id"]
	var glint: float = split["glint"]
	var b := MCMeshBuilder.new()
	b.local_origin = Vector3.ZERO
	if SPRITE_ITEMS.has(id):
		b.xform = xform * _sprite_pose(bool(SPRITE_ITEMS[id]["handheld"]))
		b.tex_size = Vector2(img.get_width(), img.get_height())
		# The builder re-applies b.xform to whatever pivot it is handed, so hand it the pivot
		# expressed in the pose's own frame and it comes back out in character space.
		_extrude_sprite(b, img, glint, part_id, b.xform.affine_inverse() * pivot_px)
		return b.commit()
	var boxes: Array = []
	var tex_size := Vector2(img.get_width(), img.get_height())
	if BOX_ITEMS.has(id):
		var entry: Dictionary = BOX_ITEMS[id]
		boxes = entry["boxes"]
		tex_size = entry["tex_size"]
		var rot: Vector3 = entry.get("rot", Vector3.ZERO)
		var pose := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
		if bool(entry.get("upright", false)):
			pose = MCGeometry.held_item_basis().inverse() * pose
		b.xform = xform * Transform3D(pose, Vector3.ZERO)
	elif CUBE_ITEMS.has(id):
		var s: float = float(CUBE_ITEMS[id]["size"])
		boxes = [{"min": Vector3(-s * 0.5, 0, -s * 0.5), "size": Vector3(s, s, s),
			"uv": Vector2i(0, 0), "uv_dims": Vector3i(16, 16, 16)}]
		tex_size = Vector2(64, 32)
		b.xform = xform
	else:
		return null
	b.tex_size = tex_size
	var local_pivot: Vector3 = b.xform.affine_inverse() * pivot_px
	for box in boxes:
		b.add_skin_box(box["min"], box["size"], box["uv"], box["uv_dims"], false, 0.0,
			part_id, local_pivot, glint)
	return b.commit()

## Vanilla's display transform for a held sprite, reduced to what matters here: `handheld` rolls the
## sprite 45 degrees so the handle-to-tip diagonal points up out of the fist, `generated` leaves it
## upright. Either way the grip ends up at the origin with the item extending +Y, which is the same
## contract the box models use, so the hand socket does not need to know which kind it is holding.
static func _sprite_pose(handheld: bool) -> Transform3D:
	var half := 8.0 * ITEM_SCALE
	if not handheld:
		return Transform3D(Basis.IDENTITY, Vector3(0, half, 0))
	var basis := Basis.from_euler(Vector3(0, 0, deg_to_rad(45.0)))
	# The handle is the sprite's bottom-left corner; after the roll it sits at -sqrt(2) * half.
	return Transform3D(basis, Vector3(0, sqrt(2.0) * half, 0))

## Extrudes a sprite into a slab. `b.xform` must already carry the pose.
static func _extrude_sprite(b: MCMeshBuilder, src: Image, glint: float, part_id: int,
		pivot_px: Vector3) -> void:
	var img := src
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return
	# HD packs ship the same sprite at a multiple of 16; keep the physical size and just sample finer.
	var sx := ITEM_SCALE * 16.0 / float(w)
	var sy := ITEM_SCALE * 16.0 / float(h)
	var hd := ITEM_DEPTH_PX * 0.5
	var x0 := -float(w) * sx * 0.5
	var x1 := -x0
	var y0 := -float(h) * sy * 0.5
	var y1 := -y0

	# Front (-Z) and back (+Z): the whole sprite, alpha-scissored by the shader.
	b.add_quad(Vector3(x1, y1, -hd), Vector3(x0, y1, -hd), Vector3(x0, y0, -hd), Vector3(x1, y0, -hd),
		Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector3(0, 0, -1),
		part_id, pivot_px, glint)
	b.add_quad(Vector3(x0, y1, hd), Vector3(x1, y1, hd), Vector3(x1, y0, hd), Vector3(x0, y0, hd),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector3(0, 0, 1),
		part_id, pivot_px, glint)

	# Rim: a side quad wherever an opaque pixel meets a transparent one or the sprite's border.
	for py in h:
		for px in w:
			if img.get_pixel(px, py).a <= ALPHA_CUT:
				continue
			# Sample the pixel's own centre, so the rim takes that pixel's colour.
			var uv := Vector2((float(px) + 0.5) / float(w), (float(py) + 0.5) / float(h))
			var lx := x0 + float(px) * sx
			var rx := lx + sx
			# Sprite row 0 is the top of the item, so y runs the other way.
			var ty := y1 - float(py) * sy
			var by := ty - sy
			if px == 0 or img.get_pixel(px - 1, py).a <= ALPHA_CUT:
				b.add_quad(Vector3(lx, ty, -hd), Vector3(lx, ty, hd), Vector3(lx, by, hd),
					Vector3(lx, by, -hd), uv, uv, uv, uv, Vector3(-1, 0, 0), part_id, pivot_px, glint)
			if px == w - 1 or img.get_pixel(px + 1, py).a <= ALPHA_CUT:
				b.add_quad(Vector3(rx, ty, hd), Vector3(rx, ty, -hd), Vector3(rx, by, -hd),
					Vector3(rx, by, hd), uv, uv, uv, uv, Vector3(1, 0, 0), part_id, pivot_px, glint)
			if py == 0 or img.get_pixel(px, py - 1).a <= ALPHA_CUT:
				b.add_quad(Vector3(lx, ty, hd), Vector3(rx, ty, hd), Vector3(rx, ty, -hd),
					Vector3(lx, ty, -hd), uv, uv, uv, uv, Vector3(0, 1, 0), part_id, pivot_px, glint)
			if py == h - 1 or img.get_pixel(px, py + 1).a <= ALPHA_CUT:
				b.add_quad(Vector3(lx, by, -hd), Vector3(rx, by, -hd), Vector3(rx, by, hd),
					Vector3(lx, by, hd), uv, uv, uv, uv, Vector3(0, -1, 0), part_id, pivot_px, glint)

## Lays a block's three faces out in the standard box net (64x32 for a 16-cube) so a cube can be
## textured with add_skin_box like any other part.
static func _cube_net(entry: Dictionary) -> Image:
	var side := ResourcePack.block_image(String(entry["side"]))
	if side == null:
		return null
	var top := ResourcePack.block_image(String(entry["top"]))
	var bottom := ResourcePack.block_image(String(entry["bottom"]))
	if top == null:
		top = side
	if bottom == null:
		bottom = top
	var n := side.get_width()
	var net := Image.create_empty(n * 4, n * 2, false, Image.FORMAT_RGBA8)
	var whole := func(img: Image) -> Rect2i: return Rect2i(Vector2i.ZERO, img.get_size())
	for i in 4:
		net.blit_rect(side, whole.call(side), Vector2i(i * n, n))
	net.blit_rect(top, whole.call(top), Vector2i(n, 0))
	net.blit_rect(bottom, whole.call(bottom), Vector2i(n * 2, 0))
	return net

static func _tint(img: Image, colour: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * colour.r, c.g * colour.g, c.b * colour.b, c.a))
