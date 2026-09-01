extends Node3D
## Photographs every model in the game, one at a time, on a studio backdrop.
##
## The in-game screenshots show models where they live - lit by the level, half
## in shadow, partly behind something else. That is the right way to judge
## whether a scene works and the wrong way to judge whether a MODEL works. This
## puts each one alone on a neutral sweep under three-point lighting at a fixed
## three-quarter angle, so shape, proportion and detail are all that is left to
## look at.
##
##   usage: tools/render_models.sh <godot> [out-dir]
##
## Like every other capture here, this runs on a software rasteriser under Xvfb
## because the machine has no GPU. See tools/screenshot.gd for what that does
## and does not reproduce.

const SHOT_SIZE := Vector2i(560, 560)

var _out_dir: String = "captures/models"
var _stage: Node3D
var _camera: Camera3D
var _saved: int = 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--out="):
			_out_dir = String(arg).split("=", true, 1)[1]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	get_window().size = SHOT_SIZE
	_build_studio()

	for entry in CATALOGUE:
		await _photograph(String(entry[0]), float(entry[1]))

	print("GALLERY %d images -> %s" % [_saved, _out_dir])
	get_tree().quit()


# --------------------------------------------------------------------------
# The studio
# --------------------------------------------------------------------------

func _build_studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.10, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.56)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 2.4
	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# A sweep, so the model has a floor to cast onto and no visible corner.
	var floor_instance := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(40.0, 40.0)
	floor_mesh.subdivide_width = 20
	floor_mesh.subdivide_depth = 20
	floor_instance.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.20, 0.22, 0.27)
	floor_material.roughness = 0.85
	floor_material.metallic = 0.0
	floor_instance.material_override = floor_material
	add_child(floor_instance)

	# Three-point lighting. The key does the shaping, the fill keeps the shadow
	# side readable, and the rim separates the model from the backdrop - which
	# is the whole reason a dark model on a dark floor is still legible here.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 38.0, 0.0)
	key.light_energy = 2.1
	key.light_color = Color(1.0, 0.97, 0.92)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 24.0
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, -62.0, 0.0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.72, 0.82, 1.0)
	add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-8.0, 196.0, 0.0)
	rim.light_energy = 1.5
	rim.light_color = Color(0.65, 0.85, 1.0)
	add_child(rim)

	_stage = Node3D.new()
	add_child(_stage)

	_camera = Camera3D.new()
	_camera.fov = 38.0
	_camera.near = 0.02
	add_child(_camera)
	_camera.current = true


## Frames the subject from a fixed three-quarter angle, so every model in the
## gallery is shot the same way and they can be compared to each other.
func _frame(height: float) -> void:
	var distance: float = maxf(height, 0.25) * 2.35
	var eye := Vector3(0.62, 0.52, 1.0).normalized() * distance
	var target := Vector3(0.0, height * 0.45, 0.0)
	_camera.look_at_from_position(eye + Vector3(0.0, height * 0.42, 0.0), target, Vector3.UP)


func _photograph(name: String, height: float) -> void:
	for child in _stage.get_children():
		_stage.remove_child(child)
		child.free()

	var subject := Node3D.new()
	# Everything in this game faces -Z, and the camera stands at +X/+Z, so an
	# unturned subject is photographed from behind. Turn it to meet the camera.
	subject.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	_stage.add_child(subject)
	_build(name, subject)
	_frame(height)

	await _frames(4)
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out_dir, name]
	if get_viewport().get_texture().get_image().save_png(path) == OK:
		_saved += 1
		print("  model %s" % path)
	else:
		push_error("could not save %s" % path)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


# --------------------------------------------------------------------------
# What gets photographed
# --------------------------------------------------------------------------

## Name and the subject's approximate height in metres, which is all the framing
## needs. Written as a flat list with a `match` builder rather than an array of
## lambdas: multi-line lambdas inside an array literal parse, but they hide
## errors in a wall of punctuation and every one of them has to be read twice.
const CATALOGUE: Array = [
	["01-explorer", 1.9],
	["02-explorer-downed", 1.9],
	["03-blaster", 0.7],
	["04-sentinel", 2.6],
	["05-pedestal", 1.8],
	["06-altar", 3.4],
	["07-terminal", 2.1],
	["08-drop-pod", 4.4],
	["09-power-crystal", 2.0],
	["10-star-map", 1.5],
	["11-rocks", 2.4],
	["12-scatter", 4.4],
	["13-primitives", 2.9],
]


func _build(name: String, root: Node3D) -> void:
	match name:
		"01-explorer":
			_explorer(root, false)
		"02-explorer-downed":
			_explorer(root, true)
		"03-blaster":
			var weapon: Node3D = load("res://scripts/player/view_model.gd").new()
			root.add_child(weapon)
			# The viewmodel parks itself in front of a camera and points away
			# from it. Recentre and turn it so the gallery sees the weapon.
			weapon.position = Vector3(0.0, 0.36, 0.0)
			weapon.rotation_degrees = Vector3(0.0, -52.0, 0.0)
			weapon.scale = Vector3.ONE
		"04-sentinel":
			# Mirrors the real scene: Shell, Core and Eye are siblings, and only
			# Shell is spun at runtime.
			var mount := Node3D.new()
			mount.position = Vector3(0.0, 1.5, 0.0)
			root.add_child(mount)
			var shell := MeshInstance3D.new()
			mount.add_child(shell)
			var core := MeshInstance3D.new()
			mount.add_child(core)
			var eye := MeshInstance3D.new()
			mount.add_child(eye)
			PropBuilder.build_sentinel(shell, core, eye)
			# sentinel.gd applies these three materials itself after building;
			# the gallery has to do the same or the parts render untextured.
			_lit_material(core, Color(0.72, 0.26, 0.2), Color(1.0, 0.4, 0.28), 0.9)
			_lit_material(eye, Color(1.0, 0.3, 0.24), Color(1.0, 0.3, 0.24), 1.6)
		"05-pedestal":
			var socket := MeshInstance3D.new()
			root.add_child(socket)
			PropBuilder.build_pedestal(root, socket, Color(0.35, 0.72, 1.0))
		"06-altar":
			var base := MeshInstance3D.new()
			root.add_child(base)
			PropBuilder.build_altar(root, base)
		"07-terminal":
			var case_node := MeshInstance3D.new()
			root.add_child(case_node)
			var screen := MeshInstance3D.new()
			root.add_child(screen)
			PropBuilder.build_terminal(root, case_node, screen)
			# mission_terminal.gd lights the display at runtime; without this
			# the gallery photographs a blank white slab.
			_lit_material(screen, Color(0.16, 0.35, 0.44), Color(0.45, 0.9, 1.0), 1.0)
		"08-drop-pod":
			var hull := MeshInstance3D.new()
			root.add_child(hull)
			var ring := MeshInstance3D.new()
			root.add_child(ring)
			PropBuilder.build_drop_pod(root, hull, ring)
			_lit_material(ring, Color(0.4, 0.9, 0.75), Color(0.4, 0.9, 0.75), 0.9)
		"09-power-crystal":
			_power_crystal(root)
		"10-star-map":
			_star_map(root)
		"11-rocks":
			var x := -1.6
			for seed_value in [3, 17, 41, 92]:
				ModelKit.part(root, MeshFactory.rock(Vector3(1.0, 0.85, 1.0), seed_value),
					Vector3(x, 0.45, 0.0), Color(0.44, 0.40, 0.36), 0.0, 0.92)
				x += 1.05
		"12-scatter":
			_scatter(root)
		"13-primitives":
			_primitives(root)


## Mirrors what a script would normally apply at runtime.
func _lit_material(instance: MeshInstance3D, albedo: Color, emission: Color,
		energy: float) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = energy
	instance.material_override = material


func _explorer(root: Node3D, downed: bool) -> void:
	var body: Node3D = load("res://scripts/player/player_body.gd").new()
	root.add_child(body)
	body.call("build", Color(0.30, 0.72, 1.0))
	if downed:
		body.call("set_downed", true)


## Built from the real scene rather than a hand-copied approximation, which is
## the only way this gallery stays honest as the model changes.
func _power_crystal(root: Node3D) -> void:
	# A crystal in a level is hidden until the authoritative snapshot says it is
	# collectable, and it needs an id to know its colour. The gallery supplies
	# both so the real scene can be photographed as it appears in play.
	_show_interactable(root, "res://scenes/interactables/power_crystal.tscn",
		{"object_id": "gallery_crystal", "crystal_id": GameConfig.CRYSTAL_CAVE})


func _star_map(root: Node3D) -> void:
	_show_interactable(root, "res://scenes/interactables/dropped_star_map.tscn",
		{"object_id": "gallery_star_map"})


## Instantiates a real interactable scene, sets the exports a level would set,
## and forces it visible. Without this the gallery photographs an empty studio,
## because an interactable with no authoritative snapshot behind it hides itself.
func _show_interactable(root: Node3D, path: String, properties: Dictionary) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		return
	var instance := scene.instantiate()
	for key in properties:
		instance.set(key, properties[key])
	root.add_child(instance)
	_force_visible(instance)


func _force_visible(node: Node) -> void:
	if node is Node3D:
		(node as Node3D).visible = true
	for child in node.get_children():
		_force_visible(child)


## The five set-dressing kinds side by side. These are what fill the space
## between the hand-placed landmarks, so they are worth looking at as a family:
## if two of them read the same, one of them is wasted.
func _scatter(root: Node3D) -> void:
	var script: GDScript = load("res://scripts/utility/prop_scatter.gd")
	var x := -4.4
	for kind in 5:
		var patch: Node3D = script.new()
		patch.position = Vector3(x, 0.0, 0.0)
		patch.set("kind", kind)
		patch.set("count", 5)
		patch.set("region", Vector3(1.6, 0.0, 1.6))
		patch.set("seed_value", 7 + kind)
		patch.set("min_scale", 0.7)
		patch.set("max_scale", 1.25)
		root.add_child(patch)
		x += 2.2


func _primitives(root: Node3D) -> void:
	var grey := Color(0.56, 0.59, 0.65)
	var row_one: Array = [
		MeshFactory.beveled_box(Vector3(0.8, 0.8, 0.8), 0.07),
		MeshFactory.sphere(0.42, 6, 10),
		MeshFactory.capsule(0.95, 0.24, 8),
		MeshFactory.tube(0.8, 0.3, 0.19, 12),
		MeshFactory.wedge(Vector3(0.8, 0.7, 0.8), 0.25),
	]
	var row_two: Array = [
		MeshFactory.torus(0.34, 0.1, 16, 7),
		MeshFactory.tapered_column(0.9, 0.3, 0.16, 8),
		MeshFactory.crystal(0.9, 0.26, 6),
		MeshFactory.rock(Vector3(0.85, 0.75, 0.85), 7),
	]
	var x := -2.0
	for mesh in row_one:
		ModelKit.part(root, mesh, Vector3(x, 0.5, 0.0), grey, 0.3, 0.45)
		x += 1.0
	x = -1.5
	for mesh in row_two:
		ModelKit.part(root, mesh, Vector3(x, 1.5, 0.0), grey, 0.3, 0.45)
		x += 1.0
