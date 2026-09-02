@tool
extends StaticBody3D
class_name WorldBlock
## One authored box of level geometry: mesh + collision from a single node.
##
## WHY: a level built from raw StaticBody3D/CollisionShape3D/MeshInstance3D
## triples is three times the scene text and three times the places to make a
## mistake. One node with a size and a palette entry keeps the level files
## readable and keeps mesh and collision impossible to desynchronise - they are
## generated from the same `size`.
##
## This is authored content, not procedural generation: every block's position,
## size and palette is hand-placed in the level scene.

@export var size: Vector3 = Vector3(1.0, 1.0, 1.0):
	set(value):
		size = value
		_rebuild()

@export_enum("hull", "hull_dark", "floor", "neon", "rock", "rock_dark", "foliage", "sand", "glass", "trim", "panel")
var palette: String = "hull":
	set(value):
		palette = value
		_rebuild()

## Chamfer width. Zero uses an automatic value derived from the block's smallest
## side, which is almost always what you want: a hard-edged box gives the
## renderer nothing to catch a highlight on, and a whole level of them reads as
## flat grey paper. See MeshFactory.beveled_box.
@export var bevel: float = 0.0:
	set(value):
		bevel = value
		_rebuild()

## Blocks that only decorate can skip collision entirely.
@export var solid: bool = true:
	set(value):
		solid = value
		_rebuild()

var _mesh_instance: MeshInstance3D
var _shape: CollisionShape3D


func _ready() -> void:
	collision_layer = GameConfig.LAYER_WORLD if solid else 0
	collision_mask = 0
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "BlockMesh"
		add_child(_mesh_instance)
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "BlockShape"
		add_child(_shape)

	_mesh_instance.mesh = MeshFactory.beveled_box(size, _effective_bevel())
	_mesh_instance.material_override = material_for(palette)

	var box_shape := BoxShape3D.new()
	box_shape.size = size
	_shape.shape = box_shape
	_shape.disabled = not solid
	collision_layer = GameConfig.LAYER_WORLD if solid else 0


## A chamfer proportional to the block, capped so a 140 m ground slab does not
## get a metre-wide bevel and a 0.2 m detail block does not lose its shape.
func _effective_bevel() -> float:
	if bevel > 0.0:
		return bevel
	var smallest: float = minf(size.x, minf(size.y, size.z))
	return clampf(smallest * 0.09, 0.012, 0.14)


## Shared materials - a level has ~80 blocks and they must not each allocate.
##
## Every palette is now a ShaderMaterial on `surface.gdshader`: world-space
## triplanar textures, a slope-driven overlay, a detail normal and macro
## variation. The palette colour survives as the shader's `tint`, so the level
## files and the art direction are untouched - what changed is that a wall now
## has grain, panel seams and wear instead of being one flat value.
static var _materials: Dictionary = {}
static var _shader: Shader = null
static var _textures: Dictionary = {}


static func _texture(name: String) -> Texture2D:
	if _textures.has(name):
		return _textures[name]
	var texture: Texture2D = load("res://assets/textures/%s.png" % name)
	_textures[name] = texture
	return texture


static func material_for(name: String) -> ShaderMaterial:
	if _materials.has(name):
		return _materials[name]
	if _shader == null:
		_shader = load("res://shaders/surface.gdshader")

	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("detail_normal_map", _texture("detail_normal"))

	# set: which texture family the palette draws from.
	# tint: the palette colour, unchanged from before the textures existed.
	var set_name := "hull"
	var tint := Color(0.5, 0.5, 0.5)
	var rough := 1.0
	var metal := 1.0
	var scale := 0.28
	var mix_amount := 0.85
	var overlay := ""

	match name:
		"hull":
			set_name = "hull"
			tint = Color(0.62, 0.66, 0.74)
			rough = 1.35
			metal = 0.18
			scale = 0.22
		"hull_dark":
			set_name = "hull"
			tint = Color(0.30, 0.33, 0.40)
			rough = 1.4
			metal = 0.2
			scale = 0.22
		"panel":
			set_name = "hull"
			tint = Color(0.46, 0.51, 0.60)
			rough = 1.25
			metal = 0.2
			scale = 0.34
		"trim":
			set_name = "hull"
			tint = Color(0.86, 0.90, 0.96)
			rough = 0.95
			metal = 0.4
			scale = 0.5
		"floor":
			set_name = "hull"
			tint = Color(0.40, 0.44, 0.52)
			rough = 1.45
			metal = 0.08
			scale = 0.17
		"rock":
			set_name = "rock"
			tint = Color(0.72, 0.66, 0.58)
			rough = 1.0
			metal = 0.0
			scale = 0.15
			# Dust collects on the upward faces of every outcrop.
			overlay = "sand"
		"rock_dark":
			set_name = "rock"
			tint = Color(0.40, 0.37, 0.35)
			rough = 1.05
			metal = 0.0
			scale = 0.15
			overlay = "sand"
		"sand":
			set_name = "sand"
			tint = Color(0.86, 0.80, 0.66)
			rough = 1.0
			metal = 0.0
			scale = 0.22
		"foliage":
			set_name = "moss"
			tint = Color(0.72, 0.92, 0.70)
			rough = 1.0
			metal = 0.0
			scale = 0.3
		"neon":
			# Emissive strips carry no texture at all: a light source with
			# panel seams on it reads as a printed sticker.
			set_name = ""
			tint = Color(0.24, 0.82, 1.0)
			mix_amount = 0.0
		"glass":
			set_name = ""
			tint = Color(0.05, 0.08, 0.16)
			mix_amount = 0.0
		_:
			set_name = "hull"
			tint = Color(0.5, 0.5, 0.5)

	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("texture_scale", scale)
	m.set_shader_parameter("roughness_scale", rough)
	m.set_shader_parameter("metallic_scale", metal)
	m.set_shader_parameter("albedo_texture_mix", mix_amount)

	if set_name != "":
		m.set_shader_parameter("albedo_map", _texture("%s_albedo" % set_name))
		m.set_shader_parameter("normal_map", _texture("%s_normal" % set_name))
		m.set_shader_parameter("roughness_map", _texture("%s_roughness" % set_name))
		if set_name == "hull":
			m.set_shader_parameter("metallic_map", _texture("hull_metallic"))
		# 0.6 at 2.4 repeats/metre put a bright speckle over every hull surface:
		# the detail normal was fine enough to alias against the pixel grid and
		# read as glitter rather than as texture.
		m.set_shader_parameter("detail_strength", 0.28)
		m.set_shader_parameter("detail_scale", 0.9)
		m.set_shader_parameter("detail_distance", 9.0)
	else:
		m.set_shader_parameter("detail_strength", 0.0)
		m.set_shader_parameter("normal_strength", 0.0)

	if overlay != "":
		m.set_shader_parameter("overlay_enabled", true)
		m.set_shader_parameter("overlay_albedo", _texture("%s_albedo" % overlay))
		m.set_shader_parameter("overlay_normal", _texture("%s_normal" % overlay))
		m.set_shader_parameter("overlay_tint", Color(0.80, 0.74, 0.60))
		m.set_shader_parameter("overlay_scale", 0.2)
		m.set_shader_parameter("overlay_amount", 0.7)

	if name == "neon":
		m.set_shader_parameter("emission_colour", tint)
		m.set_shader_parameter("emission_energy", 0.85)
	if name == "glass":
		m.set_shader_parameter("emission_colour", Color(0.1, 0.2, 0.4))
		m.set_shader_parameter("emission_energy", 0.15)

	_materials[name] = m
	return m
