class_name MCMaterials
extends RefCounted
## Creates ShaderMaterials for character meshes. Shared textures are cached statically.

static var _shader_opaque: Shader
static var _shader_ghost: Shader
static var _armor_tex: Texture2D
static var _layer_tex: Dictionary = {}      # "material:layer" -> Texture2D
static var _glint_tex: Texture2D
static var _item_glint_tex: Texture2D
static var _item_tex: Dictionary = {}       # weapon id -> Texture2D (null when the pack has none)

static func armor_texture() -> Texture2D:
	if _armor_tex == null:
		var img := SkinParser.load_image("res://assets/textures/armor_pattern.png")
		if img == null:
			img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
		_armor_tex = ImageTexture.create_from_image(img)
	return _armor_tex

## The pack's armour layer texture for a material, or null when the pack has none.
static func armor_layer_texture(material: String, layer: int) -> Texture2D:
	var key := "%s:%d" % [material, layer]
	if _layer_tex.has(key):
		return _layer_tex[key]
	var img := ResourcePack.armor_layer(material, layer)
	_layer_tex[key] = ImageTexture.create_from_image(img) if img != null else null
	return _layer_tex[key]

## Minecraft's scrolling enchantment overlay. Null when no pack is installed.
static func glint_texture() -> Texture2D:
	if _glint_tex == null:
		var img := ResourcePack.glint_image(true)
		if img != null:
			_glint_tex = ImageTexture.create_from_image(img)
	return _glint_tex

## A material that draws an armour layer: the same character shader, but with the layer texture
## standing in for the skin so the GPU limb animation still applies.
static func make_armor_layer(material: String, layer: int, gpu_anim: bool = false,
		glint: bool = false) -> ShaderMaterial:
	var tex := armor_layer_texture(material, layer)
	if tex == null:
		return null
	var m := make(tex, false, gpu_anim)
	if glint:
		var g := glint_texture()
		if g != null:
			m.set_shader_parameter("glint_tex", g)
			m.set_shader_parameter("glint_has_tex", 1.0)
			m.set_shader_parameter("glint_strength", 1.0)
	return m

## The texture a real held item is drawn with, or null when the pack cannot draw it.
static func item_texture(weapon_id: String) -> Texture2D:
	var key: String = WeaponBuilder.split_glint(weapon_id)["id"]
	if _item_tex.has(key):
		return _item_tex[key]
	var img := WeaponBuilder.real_item_image(key)
	_item_tex[key] = ImageTexture.create_from_image(img) if img != null else null
	return _item_tex[key]

## Minecraft draws the glint over items with a different sheet than the one it uses over armour.
static func item_glint_texture() -> Texture2D:
	if _item_glint_tex == null:
		var img := ResourcePack.glint_image(false)
		if img != null:
			_item_glint_tex = ImageTexture.create_from_image(img)
	return _item_glint_tex

## A material for a held item: the character shader again, with the item's own texture in place of
## the skin so the item still animates with the arm that holds it.
static func make_item(weapon_id: String, gpu_anim: bool = false) -> ShaderMaterial:
	var tex := item_texture(weapon_id)
	if tex == null:
		return null
	var m := make(tex, false, gpu_anim)
	if float(WeaponBuilder.split_glint(weapon_id)["glint"]) > 0.0:
		var g := item_glint_texture()
		if g != null:
			m.set_shader_parameter("glint_tex", g)
			m.set_shader_parameter("glint_has_tex", 1.0)
			m.set_shader_parameter("glint_strength", 1.0)
	return m

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
