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

## Palette. Kept as constants so the weapon can be recoloured in one place, and
## so the names say what each surface is meant to be rather than what hue it is.
const BODY := Color(0.21, 0.23, 0.28)
const BODY_LIGHT := Color(0.30, 0.33, 0.39)
const BODY_DARK := Color(0.13, 0.14, 0.18)
const METAL := Color(0.55, 0.59, 0.66)
const GRIP := Color(0.11, 0.12, 0.15)
const GLASS := Color(0.06, 0.10, 0.14)
const HOSE := Color(0.16, 0.17, 0.21)
const CHARGE := Color(0.35, 0.85, 1.0)
const SIGHT_GLOW := Color(1.0, 0.45, 0.30)

var _coils: Array[MeshInstance3D] = []
var _vents: Array[MeshInstance3D] = []
var _cell: MeshInstance3D = null
var _tip: Node3D = null


func _ready() -> void:
	position = _rest_position
	rotation_degrees = _rest_rotation
	scale = Vector3.ONE * 0.78
	_build()


func _build() -> void:
	_coils.clear()
	_vents.clear()
	# The weapon points down -Z, the direction the camera looks. Everything is
	# laid out along that axis from the shoulder end (+Z) to the muzzle (-Z).
	#
	# The first version was a box with a stick through it. What was missing was
	# not detail for its own sake but the four things that make a gun read as a
	# gun at a glance: a bore you can see down, a trigger group, a magazine, and
	# a break in the silhouette between receiver and barrel.

	# --- Receiver -----------------------------------------------------------
	_part(MeshFactory.beveled_box(Vector3(0.082, 0.108, 0.30), 0.016),
		Vector3(0.0, 0.0, 0.02), BODY, 0.55, 0.38)
	# Upper housing, narrower than the receiver, so the body is not one slab.
	_part(MeshFactory.beveled_box(Vector3(0.062, 0.05, 0.26), 0.012),
		Vector3(0.0, 0.072, 0.0), BODY_LIGHT, 0.6, 0.32)
	# Ejection-side plate, offset to the right, which breaks the symmetry a
	# perfectly mirrored weapon suffers from.
	_part(MeshFactory.beveled_box(Vector3(0.014, 0.062, 0.14), 0.005),
		Vector3(0.048, 0.005, 0.03), METAL, 0.75, 0.28)

	# --- Rear brace ---------------------------------------------------------
	_part(MeshFactory.beveled_box(Vector3(0.058, 0.088, 0.09), 0.018),
		Vector3(0.0, -0.012, 0.205), BODY_DARK, 0.5, 0.45)
	_part(MeshFactory.beveled_box(Vector3(0.04, 0.05, 0.05), 0.012),
		Vector3(0.0, 0.045, 0.245), METAL, 0.7, 0.3)

	# --- Barrel group -------------------------------------------------------
	# A tube, not a cylinder: you can see down the bore, and that single detail
	# is most of what separates a weapon from a prop.
	_part(MeshFactory.tube(0.34, 0.026, 0.015, 12),
		Vector3(0.0, 0.014, -0.30), METAL, 0.85, 0.22, Vector3(90.0, 0.0, 0.0))
	# Shroud over the rear half of the barrel.
	_part(MeshFactory.tube(0.17, 0.05, 0.03, 10),
		Vector3(0.0, 0.014, -0.235), BODY, 0.6, 0.35, Vector3(90.0, 0.0, 0.0))
	# Cooling fins on the shroud.
	for i in 2:
		_part(MeshFactory.beveled_box(Vector3(0.096, 0.013, 0.016), 0.004),
			Vector3(0.0, 0.014, -0.30 - float(i) * 0.038), BODY_LIGHT, 0.65, 0.3)
	# Muzzle brake: a flared collar with prongs, so the end of the gun has a
	# shape instead of stopping dead.
	_part(MeshFactory.tube(0.06, 0.052, 0.028, 10),
		Vector3(0.0, 0.014, -0.455), BODY_DARK, 0.7, 0.3, Vector3(90.0, 0.0, 0.0))
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		_part(MeshFactory.beveled_box(Vector3(0.014, 0.014, 0.055), 0.004),
			Vector3(cos(angle) * 0.042, 0.014 + sin(angle) * 0.042, -0.478),
			METAL, 0.8, 0.25)

	# --- Sight --------------------------------------------------------------
	_part(MeshFactory.beveled_box(Vector3(0.05, 0.03, 0.075), 0.008),
		Vector3(0.0, 0.108, -0.03), BODY_DARK, 0.6, 0.35)
	_part(MeshFactory.beveled_box(Vector3(0.036, 0.042, 0.008), 0.004),
		Vector3(0.0, 0.128, -0.062), GLASS, 0.2, 0.15)
	_make_emissive(_part(MeshFactory.beveled_box(Vector3(0.026, 0.03, 0.004), 0.002),
		Vector3(0.0, 0.128, -0.066), SIGHT_GLOW, 0.1, 0.3), SIGHT_GLOW, 1.5)
	_part(MeshFactory.beveled_box(Vector3(0.012, 0.03, 0.012), 0.003),
		Vector3(0.0, 0.048, -0.36), METAL, 0.8, 0.25)

	# --- Grip and trigger group ---------------------------------------------
	_part(MeshFactory.beveled_box(Vector3(0.052, 0.175, 0.072), 0.016),
		Vector3(0.0, -0.135, 0.10), GRIP, 0.15, 0.75, Vector3(-15.0, 0.0, 0.0))
	# Finger swells, so the grip is not a flat paddle.
	for i in 3:
		_part(MeshFactory.beveled_box(Vector3(0.056, 0.016, 0.024), 0.006),
			Vector3(0.0, -0.09 - float(i) * 0.042, 0.068 + float(i) * 0.011),
			BODY_DARK, 0.2, 0.7, Vector3(-15.0, 0.0, 0.0))
	# Trigger guard: an upright ring, which is the detail your eye uses to find
	# the trigger and therefore the front of the weapon.
	_part(MeshFactory.torus(0.046, 0.011, 12, 5),
		Vector3(0.0, -0.078, 0.033), BODY_DARK, 0.5, 0.4, Vector3(90.0, 0.0, 0.0))
	_part(MeshFactory.beveled_box(Vector3(0.012, 0.042, 0.012), 0.003),
		Vector3(0.0, -0.062, 0.052), METAL, 0.8, 0.3, Vector3(-12.0, 0.0, 0.0))

	# --- Power cell ---------------------------------------------------------
	# Canted forward under the receiver, with a window showing the charge. It
	# gives the underside of the weapon a mass to balance the barrel.
	_part(MeshFactory.beveled_box(Vector3(0.058, 0.10, 0.115), 0.014),
		Vector3(0.0, -0.082, -0.03), BODY_DARK, 0.45, 0.5, Vector3(8.0, 0.0, 0.0))
	_cell = _part(MeshFactory.beveled_box(Vector3(0.062, 0.05, 0.05), 0.008),
		Vector3(0.0, -0.078, -0.084), CHARGE, 0.1, 0.3, Vector3(8.0, 0.0, 0.0))
	_make_emissive(_cell, CHARGE, 1.05)

	# --- Energy coil --------------------------------------------------------
	# Three rings around the barrel. These are the heat readout: they brighten
	# and turn orange as the blaster approaches overheating, so the gun in your
	# hands tells you what the HUD would.
	# Radius 0.058, not 0.041: at the smaller size they sat INSIDE the shroud
	# (outer radius 0.05) and were completely invisible - a heat readout you
	# cannot see is not a readout.
	for i in 3:
		var ring := _part(MeshFactory.torus(0.057, 0.0095, 16, 6),
			Vector3(0.0, 0.014, -0.175 - float(i) * 0.05), CHARGE, 0.1, 0.3,
			Vector3(90.0, 0.0, 0.0))
		_make_emissive(ring, CHARGE, 1.25)
		_coils.append(ring)

	# --- Heat vents ---------------------------------------------------------
	for side in [-1.0, 1.0]:
		for i in 3:
			var vent := _part(MeshFactory.beveled_box(Vector3(0.008, 0.03, 0.026), 0.002),
				Vector3(side * 0.043, 0.012, -0.02 + float(i) * 0.042), CHARGE, 0.1, 0.3)
			_make_emissive(vent, CHARGE, 0.8)
			_vents.append(vent)

	# --- Feed hose ----------------------------------------------------------
	# Cell to shroud. A single curved element does a lot to stop a weapon built
	# from boxes looking like it was built from boxes.
	_part(MeshFactory.capsule(0.16, 0.011, 6),
		Vector3(0.034, -0.05, -0.10), HOSE, 0.2, 0.7, Vector3(52.0, 0.0, 0.0))
	_part(MeshFactory.capsule(0.10, 0.011, 6),
		Vector3(0.034, 0.002, -0.175), HOSE, 0.2, 0.7, Vector3(14.0, 0.0, 0.0))

	# An empty marker at the muzzle. The flash pins itself here so it rides the
	# bob and the recoil with the gun instead of hanging where the barrel was.
	_tip = Node3D.new()
	_tip.name = "MuzzleTip"
	_tip.position = Vector3(0.0, 0.014, -0.50)
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
	var lit: Array = []
	lit.append_array(_coils)
	lit.append_array(_vents)
	lit.append(_cell)
	for instance in lit:
		if instance == null or not is_instance_valid(instance):
			continue
		var material := (instance as MeshInstance3D).material_override as StandardMaterial3D
		if material == null:
			continue
		material.albedo_color = colour
		material.emission = colour
		material.emission_energy_multiplier = 1.0 + clamped * 2.6
	# The cell window stays cool-coloured until the weapon is genuinely in trouble;
	# if every lit surface moved together the readout would be one big blob.
	if is_instance_valid(_cell) and not overheated:
		ModelKit.set_emission(_cell, cool.lerp(hot, clamped * 0.5), 1.05)


## Where a shot visually leaves the weapon. Not the fire origin - that stays on
## the fixed Muzzle node so aim never depends on the bob.
func muzzle_tip() -> Node3D:
	return _tip
