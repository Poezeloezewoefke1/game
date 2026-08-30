extends Node3D
## Purely cosmetic blaster tracer.
##
## It carries NO gameplay meaning: the host has already resolved the shot by the
## time this appears. That is why the broadcast that creates it is unreliable -
## a dropped tracer costs a visual, never an outcome.

const LIFETIME: float = 0.09

@onready var _beam: MeshInstance3D = $Beam

var _age: float = 0.0


func configure(from: Vector3, to: Vector3) -> void:
	var delta := to - from
	var length := maxf(delta.length(), 0.05)
	global_position = from + delta * 0.5
	if delta.length_squared() > 0.0001:
		look_at(to, Vector3.UP)
	var mesh := _beam.mesh as CylinderMesh
	if mesh != null:
		# Duplicated so concurrent tracers never fight over one shared mesh.
		mesh = mesh.duplicate() as CylinderMesh
		mesh.height = length
		_beam.mesh = mesh
	_beam.rotation_degrees = Vector3(90.0, 0.0, 0.0)


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.95, 1.0)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam.material_override = mat


func _process(delta: float) -> void:
	_age += delta
	var mat := _beam.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color.a = clampf(1.0 - _age / LIFETIME, 0.0, 1.0)
	if _age >= LIFETIME:
		queue_free()
