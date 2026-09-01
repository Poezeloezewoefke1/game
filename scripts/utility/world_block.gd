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
static func material_for(name: String) -> StandardMaterial3D:
	if _materials.has(name):
		return _materials[name]
	var m := StandardMaterial3D.new()
	# A note on `metallic`, learned the hard way from a screenshot: a metal
	# surface has no diffuse response at all - everything you see on it is
	# reflected environment. The hub is a sealed room lit by a flat background
	# colour, so there IS no environment to reflect, and every wall at
	# metallic 0.45+ rendered as a near-black slab no matter how much ambient
	# light was added. These are painted hull panels rather than bare metal,
	# and painted metal is dielectric, so the values below are both more
	# correct and the reason the room is now readable. Specular and roughness
	# carry the "this is metal" impression instead.
	match name:
		"hull":
			m.albedo_color = Color(0.40, 0.45, 0.54)
			m.metallic = 0.12
			m.roughness = 0.5
		"hull_dark":
			m.albedo_color = Color(0.19, 0.22, 0.28)
			m.metallic = 0.16
			m.roughness = 0.45
		"panel":
			m.albedo_color = Color(0.30, 0.35, 0.43)
			m.metallic = 0.14
			m.roughness = 0.4
		"trim":
			# The one genuinely bare-metal surface, kept low enough to stay lit.
			m.albedo_color = Color(0.66, 0.70, 0.76)
			m.metallic = 0.3
			m.roughness = 0.3
			m.metallic_specular = 0.75
		"floor":
			m.albedo_color = Color(0.26, 0.29, 0.36)
			m.metallic = 0.06
			m.roughness = 0.6
		"neon":
			# Kept deliberately modest. At 2.2 the floor strip was brighter than
			# everything else combined and the tonemapper crushed the rest of
			# the room to near-black around it.
			m.albedo_color = Color(0.24, 0.82, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.24, 0.82, 1.0)
			m.emission_energy_multiplier = 0.85
		"rock":
			m.albedo_color = Color(0.42, 0.38, 0.34)
			m.roughness = 0.92
		"rock_dark":
			m.albedo_color = Color(0.24, 0.22, 0.21)
			m.roughness = 0.96
		"foliage":
			m.albedo_color = Color(0.20, 0.44, 0.26)
			m.roughness = 0.88
		"sand":
			m.albedo_color = Color(0.52, 0.46, 0.35)
			m.roughness = 0.95
		"glass":
			m.albedo_color = Color(0.05, 0.08, 0.16, 0.55)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.9
			m.roughness = 0.1
		_:
			m.albedo_color = Color(0.5, 0.5, 0.5)
	_materials[name] = m
	return m
