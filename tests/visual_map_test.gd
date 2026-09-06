extends Node3D
## Diagnostic: renders the map from a high wide angle and reports what geometry was built.

var game

func _ready() -> void:
	game = load("res://scripts/core/game_controller.gd").new()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	if game.hud != null:
		game.hud.visible = false
	var mesh_nodes := 0
	var surfaces := 0
	var tex_names: Array[String] = []
	for c in game.map_builder.get_children():
		if c is MeshInstance3D:
			mesh_nodes += 1
			var mi := c as MeshInstance3D
			if mi.mesh != null:
				surfaces += mi.mesh.get_surface_count()
			var mat := mi.material_override
			if mat is StandardMaterial3D:
				var t := (mat as StandardMaterial3D).albedo_texture
				tex_names.append("tex" if t != null else "NO-TEXTURE")
	print("[MAP] map_builder children: %d, mesh instances: %d, surfaces: %d" % [
		game.map_builder.get_child_count(), mesh_nodes, surfaces])
	var with_tex := 0
	for t in tex_names:
		if t == "tex":
			with_tex += 1
	print("[MAP] materials with a texture: %d / %d" % [with_tex, tex_names.size()])
	print("[MAP] block texture cache entries: %d" % MapBuilder._block_texture_cache.size())
	for key in MapBuilder._block_texture_cache.keys():
		if MapBuilder._block_texture_cache[key] == null:
			print("[MAP]   FAILED TO LOAD: ", key)
	print("[MAP] path length %.1f, zones %d" % [game.path.total_length, game.towers.zones.size()])
	print("[MAP] faces emitted per block texture:")
	for key in game.map_builder.block_face_counts.keys():
		print("[MAP]   %-16s %d" % [key, int(game.map_builder.block_face_counts[key])])
	# high wide overview
	game._cam_target = Vector3(0, 0, 0)
	game._cam_distance = 78.0
	game._cam_yaw = 0.6
	game._cam_pitch = -1.05
	game._update_camera()
	# a few enemies so scale reads
	for i in 40:
		game.enemies.spawn("chungie_t5", game.path.total_length * float(i) / 40.0)
