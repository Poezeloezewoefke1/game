class_name MCMaterials
extends RefCounted
## Creates ShaderMaterials for character meshes. Shared textures are cached statically.

static var _shader_opaque: Shader
static var _shader_ghost: Shader
static var _armor_tex: Texture2D

static func armor_texture() -> Texture2D:
	if _armor_tex == null:
		var img := SkinParser.load_image("res://assets/textures/armor_pattern.png")
		if img == null:
			img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
		_armor_tex = ImageTexture.create_from_image(img)
	return _armor_tex

static func opaque_shader() -> Shader:
	if _shader_opaque == null:
		_shader_opaque = load("res://assets/shaders/mc_character.gdshader")
	return _shader_opaque

static func ghost_shader() -> Shader:
	if _shader_ghost == null:
		_shader_ghost = load("res://assets/shaders/mc_character_ghost.gdshader")
	return _shader_ghost

static func make(skin_tex: Texture2D, ghost: bool = false, gpu_anim: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ghost_shader() if ghost else opaque_shader()
	m.set_shader_parameter("skin_tex", skin_tex)
	m.set_shader_parameter("armor_tex", armor_texture())
	m.set_shader_parameter("anim_enabled", 1.0 if gpu_anim else 0.0)
	m.set_shader_parameter("tint", Color.WHITE)
	m.set_shader_parameter("flash", 0.0)
	m.set_shader_parameter("ghost", 0.0)
	return m
