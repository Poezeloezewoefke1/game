extends Node3D
## Diagnostic: merged-mesh rendering variants side by side (front-facing).
## A: MeshInstance3D + anim material   B: MeshInstance3D + plain material
## C: MultiMesh + anim material, custom=(0,0,0,0)   D: MultiMesh + anim material, custom=(0.3,0,0,0.8)
## E: MultiMesh + plain material   F: node-based MinecraftCharacter (reference)

func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 2.2, -7.5)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.fov = 45
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-45, 200, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.13, 0.18)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.8)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.32, 0.3)
	floor_mesh.material_override = fm
	add_child(floor_mesh)

	var armor := {"helmet": "iron", "chestplate": "iron", "leggings": "iron", "boots": "iron"}
	var mesh := SkinLibrary.get_merged_mesh("chungie", armor, "iron_sword")
	var mat_anim := SkinLibrary.get_material("chungie", false, true)
	var mat_plain := SkinLibrary.get_material("chungie", false, false)
	var xs := [-6.0, -3.6, -1.2, 1.2, 3.6, 6.0]

	var a := MeshInstance3D.new()
	a.mesh = mesh; a.material_override = mat_anim; a.position = Vector3(xs[0], 0, 0)
	add_child(a)
	var b := MeshInstance3D.new()
	b.mesh = mesh; b.material_override = mat_plain; b.position = Vector3(xs[1], 0, 0)
	add_child(b)
	add_child(_mm(mesh, mat_anim, Color(0, 0, 0, 0), xs[2]))
	add_child(_mm(mesh, mat_anim, Color(0.3, 0, 0, 0.8), xs[3]))
	add_child(_mm(mesh, mat_plain, Color(0, 0, 0, 0), xs[4]))
	var mc := MinecraftCharacter.new()
	add_child(mc)
	mc.setup(SkinLibrary.get_skin("chungie"), armor, "iron_sword")
	mc.position = Vector3(xs[5], 0, 0)
	print("mesh surfaces=", mesh.get_surface_count(), " verts=", mesh.surface_get_array_len(0), " aabb=", mesh.get_aabb())
	var arrays := mesh.surface_get_arrays(0)
	print("has custom0=", arrays[Mesh.ARRAY_CUSTOM0] != null, " has color=", arrays[Mesh.ARRAY_COLOR] != null, " fmt=", mesh.surface_get_format(0))

func _mm(mesh: ArrayMesh, mat: Material, custom: Color, x: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)))
	mm.set_instance_custom_data(0, custom)
	mm.set_instance_color(0, Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi
