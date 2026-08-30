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

@export_enum("hull", "hull_dark", "floor", "neon", "rock", "rock_dark", "foliage", "sand", "glass")
var palette: String = "hull":
	set(value):
		palette = value
		_rebuild()

## Blocks that only decorate can skip collision entirely.
@export var solid: bool = true:
	set(value):
		solid = value
		_rebuild()

var _mesh_instance: MeshInstance3D
var _shape: CollisionShape3D

static var _materials: Dictionary = {}


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

	var box := BoxMesh.new()
	box.size = size
	_mesh_instance.mesh = box
	_mesh_instance.material_override = material_for(palette)

	var box_shape := BoxShape3D.new()
	box_shape.size = size
	_shape.shape = box_shape
	_shape.disabled = not solid
	collision_layer = GameConfig.LAYER_WORLD if solid else 0


## Shared materials - a level has ~80 blocks and they must not each allocate.
static func material_for(name: String) -> StandardMaterial3D:
	if _materials.has(name):
		return _materials[name]
	var m := StandardMaterial3D.new()
	match name:
		"hull":
			m.albedo_color = Color(0.30, 0.34, 0.42)
			m.metallic = 0.55
			m.roughness = 0.45
		"hull_dark":
			m.albedo_color = Color(0.15, 0.17, 0.23)
			m.metallic = 0.6
			m.roughness = 0.4
		"floor":
			m.albedo_color = Color(0.21, 0.24, 0.31)
			m.metallic = 0.35
			m.roughness = 0.7
		"neon":
			m.albedo_color = Color(0.24, 0.82, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.24, 0.82, 1.0)
			m.emission_energy_multiplier = 2.2
		"rock":
			m.albedo_color = Color(0.35, 0.32, 0.30)
			m.roughness = 0.95
		"rock_dark":
			m.albedo_color = Color(0.19, 0.18, 0.18)
			m.roughness = 0.98
		"foliage":
			m.albedo_color = Color(0.18, 0.42, 0.24)
			m.roughness = 0.9
		"sand":
			m.albedo_color = Color(0.44, 0.39, 0.29)
			m.roughness = 1.0
		"glass":
			m.albedo_color = Color(0.05, 0.08, 0.16, 0.55)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.9
			m.roughness = 0.1
		_:
			m.albedo_color = Color(0.5, 0.5, 0.5)
	_materials[name] = m
	return m
