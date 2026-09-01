extends RefCounted
class_name ModelKit
## Shared assembly helpers for models built in code.
##
## Every builder in the project - the explorer, the weapon, the temple props -
## was growing its own near-identical "make a MeshInstance3D, make a material,
## parent it" function. This is that function, once.

## Adds a lit part and returns it, so the caller can keep a handle for anything
## it needs to animate or recolour later.
static func part(parent: Node, mesh: Mesh, position: Vector3, colour: Color,
		metallic: float = 0.25, roughness: float = 0.55,
		rotation_degrees_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = rotation_degrees_value
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.metallic = metallic
	material.roughness = roughness
	instance.material_override = material
	parent.add_child(instance)
	return instance


## A part that emits light of its own. `energy` is deliberately conservative by
## default: with glow enabled, a value that looks merely bright in isolation
## blows out to flat white and drags the tonemapper down with it.
static func emissive(parent: Node, mesh: Mesh, position: Vector3, colour: Color,
		energy: float = 1.2, rotation_degrees_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := part(parent, mesh, position, colour, 0.1, 0.4, rotation_degrees_value)
	set_emission(instance, colour, energy)
	return instance


static func set_emission(instance: MeshInstance3D, colour: Color, energy: float) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	var material := instance.material_override as StandardMaterial3D
	if material == null:
		return
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = energy


static func set_albedo(instance: MeshInstance3D, colour: Color) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	var material := instance.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = colour


## Clears anything a previous build left behind, so builders are safe to re-run.
static func clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
