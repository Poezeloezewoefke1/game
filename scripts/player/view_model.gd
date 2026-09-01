extends Node3D
## The first-person blaster: the thing the player actually looks at all game.
##
## Built from MeshFactory parts rather than authored, so the shape and the
## reasoning for it stay together.
##
## It carries most of the game's sense of weight. A weapon welded rigidly to the
## camera reads as a sticker on the screen; the bob, sway and recoil below are
## what make it feel held. All of it is presentation - none of it touches
## authority, and the host neither knows nor cares that it exists.

const BOB_FREQUENCY := 7.5
const BOB_AMOUNT := 0.018
const SWAY_AMOUNT := 0.035
const SWAY_SMOOTH := 9.0
const RECOIL_KICK := 0.055
const RECOIL_RECOVER := 9.0

# Held further out and scaled down from the first pass, where the weapon filled
# the bottom-right quarter of the screen and read as a black wedge rather than a
# gun. A viewmodel should sit at the edge of attention, not compete with the
# room.
var _rest_position := Vector3(0.20, -0.155, -0.40)
## A slight inward yaw and downward pitch, so the weapon is seen in three
## quarters rather than flat side-on.
var _rest_rotation := Vector3(-2.0, 4.0, 2.0)
var _bob_time: float = 0.0
var _sway := Vector2.ZERO
var _sway_target := Vector2.ZERO
var _recoil: float = 0.0

var _coil: MeshInstance3D = null
var _vent: MeshInstance3D = null
var _tip: Node3D = null


func _ready() -> void:
	position = _rest_position
	rotation_degrees = _rest_rotation
	scale = Vector3.ONE * 0.78
	_build()


func _build() -> void:
	# Receiver
	_part(MeshFactory.beveled_box(Vector3(0.09, 0.1, 0.34), 0.018),
		Vector3(0.0, 0.0, 0.0), Color(0.2, 0.22, 0.27), 0.6, 0.35)
	# Barrel
	_part(MeshFactory.tapered_column(0.3, 0.028, 0.022, 8),
		Vector3(0.0, 0.012, -0.3), Color(0.3, 0.33, 0.38), 0.8, 0.25,
		Vector3(90.0, 0.0, 0.0))
	# Muzzle shroud
	_part(MeshFactory.beveled_box(Vector3(0.07, 0.07, 0.08), 0.015),
		Vector3(0.0, 0.012, -0.44), Color(0.16, 0.18, 0.22), 0.7, 0.3)
	# Grip, angled the way a hand actually holds one
	_part(MeshFactory.beveled_box(Vector3(0.055, 0.17, 0.07), 0.015),
		Vector3(0.0, -0.12, 0.09), Color(0.14, 0.15, 0.18), 0.2, 0.7,
		Vector3(-12.0, 0.0, 0.0))
	# Top rail
	_part(MeshFactory.beveled_box(Vector3(0.045, 0.03, 0.2), 0.008),
		Vector3(0.0, 0.066, -0.06), Color(0.26, 0.29, 0.34), 0.7, 0.3)

	# Energy coil - brightens with heat, which is the whole readout in one glance
	_coil = _part(MeshFactory.tapered_column(0.16, 0.036, 0.036, 6),
		Vector3(0.0, 0.012, -0.14), Color(0.35, 0.85, 1.0), 0.1, 0.3,
		Vector3(90.0, 0.0, 0.0))
	_make_emissive(_coil, Color(0.35, 0.85, 1.0), 2.2)

	# Heat vent along the side
	_vent = _part(MeshFactory.beveled_box(Vector3(0.012, 0.045, 0.16), 0.004),
		Vector3(0.05, 0.02, -0.04), Color(0.35, 0.85, 1.0), 0.1, 0.3)
	_make_emissive(_vent, Color(0.35, 0.85, 1.0), 1.2)

	# An empty marker at the front face of the shroud. The muzzle flash pins
	# itself here so it rides the bob and the recoil with the gun instead of
	# hanging in the air where the barrel used to be.
	_tip = Node3D.new()
	_tip.name = "MuzzleTip"
	_tip.position = Vector3(0.0, 0.012, -0.5)
	add_child(_tip)


func _part(mesh: Mesh, offset: Vector3, colour: Color, metallic: float, roughness: float,
		rotation_degrees_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := ModelKit.part(self, mesh, offset, colour, metallic, roughness,
		rotation_degrees_value)
	# The viewmodel is centimetres from the camera; letting it cast shadows
	# produces a huge blob across the whole scene.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A weapon lit only by the scene is a black silhouette in every dark room,
	# which is most of the game. A little self-illumination keeps its shape
	# readable without making it look like it is glowing.
	var material := instance.material_override as StandardMaterial3D
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 0.35
	return instance


func _make_emissive(instance: MeshInstance3D, colour: Color, energy: float) -> void:
	ModelKit.set_emission(instance, colour, energy)


# ==========================================================================
# Motion
# ==========================================================================

## `speed_ratio` is 0 when standing still and 1 at sprint speed.
func update_motion(delta: float, speed_ratio: float, grounded: bool) -> void:
	if grounded and speed_ratio > 0.05:
		_bob_time += delta * BOB_FREQUENCY * (0.6 + speed_ratio)
	else:
		# Settle rather than freeze mid-stride.
		_bob_time = lerp_angle(_bob_time, 0.0, clampf(delta * 6.0, 0.0, 1.0))

	_sway = _sway.lerp(_sway_target, clampf(delta * SWAY_SMOOTH, 0.0, 1.0))
	_sway_target = _sway_target.lerp(Vector2.ZERO, clampf(delta * SWAY_SMOOTH * 0.5, 0.0, 1.0))
	_recoil = move_toward(_recoil, 0.0, delta * RECOIL_RECOVER * maxf(_recoil, 0.05))

	# A figure-eight: horizontal at half the vertical rate is what reads as a
	# walk rather than a bounce.
	var bob := Vector3(
		sin(_bob_time * 0.5) * BOB_AMOUNT * 1.4 * speed_ratio,
		-absf(sin(_bob_time)) * BOB_AMOUNT * speed_ratio,
		0.0)

	position = _rest_position + bob + Vector3(-_sway.x, -_sway.y, _recoil)
	rotation_degrees = _rest_rotation + Vector3(
		_sway.y * 40.0 - _recoil * 120.0,
		_sway.x * 40.0,
		_sway.x * 25.0)


## Fed the mouse movement, so the weapon lags behind a fast turn.
func add_look_sway(relative: Vector2) -> void:
	_sway_target += Vector2(
		clampf(-relative.x * 0.0006, -SWAY_AMOUNT, SWAY_AMOUNT),
		clampf(-relative.y * 0.0006, -SWAY_AMOUNT, SWAY_AMOUNT))
	_sway_target = _sway_target.limit_length(SWAY_AMOUNT)


func kick() -> void:
	_recoil = minf(_recoil + RECOIL_KICK, RECOIL_KICK * 1.8)


## Heat drives the coil and vent glow, so the weapon itself tells you how close
## to overheating you are without looking at the HUD.
func set_heat_ratio(ratio: float, overheated: bool) -> void:
	var clamped := clampf(ratio, 0.0, 1.0)
	var cool := Color(0.35, 0.85, 1.0)
	var hot := Color(1.0, 0.42, 0.2)
	var colour := cool.lerp(hot, clamped)
	if overheated:
		colour = Color(1.0, 0.25, 0.15)
	for instance in [_coil, _vent]:
		if instance == null or not is_instance_valid(instance):
			continue
		var material := (instance as MeshInstance3D).material_override as StandardMaterial3D
		if material == null:
			continue
		material.albedo_color = colour
		material.emission = colour
		material.emission_energy_multiplier = 1.2 + clamped * 3.0


## Where a shot visually leaves the weapon. Not the fire origin - that stays on
## the fixed Muzzle node so aim never depends on the bob.
func muzzle_tip() -> Node3D:
	return _tip
