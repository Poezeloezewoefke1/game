extends Node
## For every enemy that carries a weapon, reports whether the MultiMesh path draws it from real
## Minecraft art and whether the merged skin mesh correctly leaves it out (drawing it twice, once as
## boxes and once as a sprite, is the failure mode this catches).
##   godot --headless --path . -s tests/run_headless.gd -- res://tests/enemy_item_check.gd 2

func _ready() -> void:
	print("\n=========== ENEMY HELD ITEMS ===========")
	var real := 0
	var boxes := 0
	for id in DataDB.enemies.keys():
		var d: Dictionary = DataDB.enemies[id]
		var held := String(d.get("held", ""))
		if held == "" or String(d.get("model", "")) != "":
			continue
		var skin_id := String(d.get("skin", "chungie"))
		var slim: bool = SkinLibrary.get_skin(skin_id).slim
		var item := SkinLibrary.get_held_item_mesh(held, slim)
		var mat := MCMaterials.make_item(held, true)
		# The merged skin mesh must not also contain the item.
		var with_item := MCMeshBuilder.build_merged_character(SkinLibrary.get_skin(skin_id), {}, held)
		var without := MCMeshBuilder.build_merged_character(SkinLibrary.get_skin(skin_id), {}, "")
		var merged_carries_boxes := with_item.surface_get_array_len(0) != without.surface_get_array_len(0)
		if item.is_empty() or mat == null:
			boxes += 1
			print("  BOXES %-20s %-26s merged_boxes=%s" % [id, held, merged_carries_boxes])
			continue
		real += 1
		var mesh: ArrayMesh = item["mesh"]
		var ok := not merged_carries_boxes
		print("  %s  %-20s %-26s verts=%-5d merged_boxes=%s" % [
			"REAL " if ok else "DOUBLE", id, held, mesh.surface_get_array_len(0), merged_carries_boxes])
	print("real=%d boxes=%d" % [real, boxes])
	print("========================================")
	get_tree().quit(0)
