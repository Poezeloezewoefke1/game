extends Node3D
## Visual check: a line-up of generated characters (skins, armor tiers, weapons) plus GPU-animated MultiMesh enemies.
## Loaded by tests/run_visual.gd.

var chars: Array = []

func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 2.8, -8.0)
	cam.look_at(Vector3(0, 1.0, 1.0))
	cam.fov = 45
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-50, 210, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.1, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.7)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.25, 0.3, 0.25)
	floor_mesh.material_override = fm
	add_child(floor_mesh)

	var lineup := [
		["uv_test", {}, "", "idle"],
		["wemmbu", {"chestplate": "netherite_enchanted", "leggings": "netherite", "boots": "netherite"}, "netherite_mace_enchanted", "walk"],
		["parrotx2", {"helmet": "gold", "chestplate": "royal", "cape": "royal"}, "royal_banner", "idle"],
		["flamefrags", {"helmet": "diamond", "chestplate": "diamond", "leggings": "diamond", "boots": "diamond"}, "diamond_sword", "attack"],
		["spokeishere", {}, "bow", "idle"],
		["saparata", {"helmet": "netherite_enchanted", "chestplate": "netherite_enchanted", "leggings": "netherite_enchanted", "boots": "netherite_enchanted", "crown": "gold"}, "netherite_mace", "walk"],
		["uv_test_legacy", {"helmet": "leather", "chestplate": "iron"}, "iron_axe", "idle"],
	]
	var x := -6.0
	for entry in lineup:
		var mc := MinecraftCharacter.new()
		add_child(mc)
		var skin: SkinData = SkinLibrary.get_skin(entry[0])
		mc.setup(skin, entry[1], entry[2])
		mc.position = Vector3(x, 0, 0)
		mc.attack_style = "slash"
		mc.play(entry[3], 1.0)
		chars.append(mc)
		print("built ", skin.describe(), " parts=", mc.parts.size(), " armor=", mc.armor_nodes.size())
		x += 2.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = SkinLibrary.get_merged_mesh("chungie", {"helmet": "iron", "chestplate": "iron", "leggings": "iron", "boots": "iron"}, "iron_sword")
	mm.instance_count = 8
	for i in 8:
		mm.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(0, PI * 0.15 * i, 0)), Vector3(-7 + i * 2.0, 0, 3)))
		mm.set_instance_custom_data(i, Color(i / 8.0, 0.0, 0.0, 0.8))
		mm.set_instance_color(i, Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = SkinLibrary.get_material("chungie", false, true)
	add_child(mmi)
	print("multimesh instances=", mm.instance_count, " mesh verts=", mm.mesh.surface_get_array_len(0))

func on_frame(f: int) -> void:
	# Re-trigger the attack so the screenshot catches mid-swing.
	if f == 20 and chars.size() > 3:
		chars[3].play("attack", 0.6)
