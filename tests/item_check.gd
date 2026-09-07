extends Node
## Reports, for every weapon id the game data actually uses, whether it is drawn from real Minecraft
## art or has fallen back to the coloured boxes, and how big the resulting mesh is.
##   godot --headless --path . -s tests/run_headless.gd -- res://tests/item_check.gd 2

const WEAPONS := [
	"wood_sword", "iron_sword", "diamond_sword", "diamond_sword_enchanted",
	"netherite_sword", "netherite_sword_enchanted", "netherite_axe",
	"netherite_mace_enchanted", "bow", "crossbow", "iron_spear", "shield",
	"stick", "potion", "totem", "pearl", "book", "firework", "tnt",
	"banner", "royal_banner", "cinder_banner",
]

func _ready() -> void:
	print("\n=========== HELD ITEM SOURCES ===========")
	print("resource pack: %s" % (ResourcePack.root() if ResourcePack.available() else "NONE"))
	var real := 0
	for w in WEAPONS:
		var img := WeaponBuilder.real_item_image(w)
		if img == null:
			print("  BOXES  %-26s (no pack art)" % w)
			continue
		real += 1
		var mesh := WeaponBuilder.build_real_mesh(w, MCMeshBuilder.hand_transform(false),
			MCMeshBuilder.hand_pivot(false))
		var aabb := mesh.get_aabb() if mesh != null else AABB()
		var kind := "sprite"
		var base: String = WeaponBuilder.split_glint(w)["id"]
		if WeaponBuilder.BOX_ITEMS.has(base):
			kind = "boxmodel"
		elif WeaponBuilder.CUBE_ITEMS.has(base):
			kind = "blockcube"
		print("  REAL   %-26s %-9s tex=%dx%d verts=%-5d size=(%.2f, %.2f, %.2f) at %s" % [
			w, kind, img.get_width(), img.get_height(),
			mesh.surface_get_array_len(0) if mesh != null else 0,
			aabb.size.x, aabb.size.y, aabb.size.z, aabb.position])
	print("real art: %d / %d" % [real, WEAPONS.size()])
	# The hand socket contract: the grip sits at the origin of the item frame, so a standalone mesh
	# must start at y ~= 0 and extend upward, exactly like the box models it replaces.
	for w in ["iron_sword", "potion", "shield"]:
		var m := WeaponBuilder.build_real_mesh(w)
		if m != null:
			print("  grip check %-14s aabb %s size %s" % [w, m.get_aabb().position, m.get_aabb().size])
	print("=========================================")
	get_tree().quit(0)
