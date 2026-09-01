extends Node3D
## Renders every MeshFactory shape side by side, so new geometry can be looked
## at without hunting for it inside a level.
##
##   tools/preview_meshes.sh <godot-binary> [output-dir]

var _out_dir: String = "captures"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--out="):
			_out_dir = String(arg).split("=", true, 1)[1]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_build()
	_shoot.call_deferred()


func _build() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.10)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.42, 0.55)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	key.light_energy = 1.5
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 140.0, 0.0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.6, 0.75, 1.0)
	add_child(fill)

	var specimens: Array = [
		["beveled box", MeshFactory.beveled_box(Vector3(1.4, 1.4, 1.4), 0.12),
			Color(0.42, 0.47, 0.56)],
		["hard box (before)", BoxMesh.new(), Color(0.42, 0.47, 0.56)],
		["crystal", MeshFactory.crystal(1.5, 0.34, 6), Color(1.0, 0.62, 0.25)],
		["prism (before)", PrismMesh.new(), Color(1.0, 0.62, 0.25)],
		["rock A", MeshFactory.rock(Vector3(1.5, 1.3, 1.4), 11), Color(0.38, 0.35, 0.32)],
		["rock B", MeshFactory.rock(Vector3(1.5, 1.3, 1.4), 77), Color(0.38, 0.35, 0.32)],
		["column", MeshFactory.tapered_column(1.8, 0.5, 0.34, 8), Color(0.5, 0.47, 0.42)],
		["thin panel", MeshFactory.beveled_box(Vector3(1.8, 1.6, 0.18), 0.05),
			Color(0.3, 0.55, 0.7)],
	]

	var columns := 4
	for i in specimens.size():
		var entry: Array = specimens[i]
		var instance := MeshInstance3D.new()
		instance.mesh = entry[1]
		var material := StandardMaterial3D.new()
		material.albedo_color = entry[2]
		material.metallic = 0.25
		material.roughness = 0.45
		instance.material_override = material
		instance.position = Vector3(
			(i % columns) * 2.6 - 3.9, 0.0, floori(float(i) / float(columns)) * 2.6 - 1.3)
		add_child(instance)

		var label := Label3D.new()
		label.text = String(entry[0])
		label.pixel_size = 0.006
		label.position = instance.position + Vector3(0.0, -1.15, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 4.2, 6.4)
	camera.look_at_from_position(camera.position, Vector3(0.0, -0.2, 0.0), Vector3.UP)
	camera.fov = 55.0
	add_child(camera)


func _shoot() -> void:
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/meshes.png" % _out_dir
	print("SAVED %s -> %d" % [path, image.save_png(path)])
	get_tree().quit(0)
