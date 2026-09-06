class_name CharacterPreview
extends SubViewportContainer
## Renders a live 3D MinecraftCharacter into a UI rect (hero select, tower shop, codex).

var viewport: SubViewport
var character: MinecraftCharacter
var pivot: Node3D
var spin_speed: float = 0.6
var _angle: float = 0.0

func _init(size: Vector2i = Vector2i(240, 300)) -> void:
	stretch = true
	custom_minimum_size = Vector2(size)
	viewport = SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	# Each preview needs its own 3D world; otherwise every preview shares the parent viewport's
	# world and all the characters pile up in the same place.
	viewport.own_world_3d = true
	add_child(viewport)
	pivot = Node3D.new()
	viewport.add_child(pivot)
	var cam := Camera3D.new()
	cam.fov = 40
	# The viewport is not in the scene tree yet, so the transform is built directly rather than
	# with look_at() (which requires a live tree).
	var cam_pos := Vector3(0, 1.15, 3.7)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.0, 0) - cam_pos, Vector3.UP), cam_pos)
	pivot.add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 155, 0)
	key.light_energy = 1.5
	pivot.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -40, 0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.7, 0.75, 1.0)
	pivot.add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.8)
	e.ambient_light_energy = 0.85
	env.environment = e
	pivot.add_child(env)

func show_character(skin_id: String, armor: Dictionary = {}, weapon: String = "", anim: String = "idle") -> void:
	if is_instance_valid(character):
		character.queue_free()
	character = MinecraftCharacter.new()
	viewport.add_child(character)
	character.setup(SkinLibrary.get_skin(skin_id), armor, weapon)
	character.position = Vector3(0, 0, 0)
	character.play(anim)

func _process(delta: float) -> void:
	if is_instance_valid(character):
		_angle += delta * spin_speed
		character.rotation.y = sin(_angle) * 0.55 + PI

func play(anim: String, duration: float = 0.6) -> void:
	if is_instance_valid(character):
		character.play(anim, duration)
