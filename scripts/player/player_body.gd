extends Node3D
## The explorer: the figure your crewmates see walking around Nerava.
##
## Assembled in code rather than authored in the scene so the whole suit can be
## recoloured per player from one place, and so the proportions live next to the
## comments explaining them. Nothing here is a downloaded asset.
##
## HIDDEN FOR THE LOCAL PLAYER: in first person you are inside this, so the
## owning player's copy is switched off entirely. Remote players see it.
##
## PROPORTIONS. The figure is 1.8 m to the crown, matching the collision
## capsule, and is laid out from the ground up in the constants below rather
## than by eye - an astronaut that reads correctly is mostly a question of the
## helmet being small enough and the shoulders being wide enough, and both are
## easy to lose while nudging numbers. Every limb is a capsule with a sphere at
## the joint, because a stack of boxes has no elbows and reads as a robot.

const SUIT := Color(0.84, 0.86, 0.90)          ## the white outer layer
const SUIT_SHADE := Color(0.62, 0.65, 0.71)    ## soft joints, where it creases
const HARD := Color(0.22, 0.24, 0.30)          ## boots, gloves, hard fittings
const HARD_LIGHT := Color(0.40, 0.44, 0.52)
const TRIM := Color(0.72, 0.76, 0.82)          ## bare metal rings and clasps
const VISOR := Color(0.05, 0.09, 0.14)         ## the glass itself, nearly black
const VISOR_GLINT := Color(0.16, 0.85, 1.0)    ## what is lit up behind it

const HIP_Y := 0.97
const CHEST_Y := 1.30
const SHOULDER_Y := 1.40
const SHOULDER_X := 0.245
const HELMET_Y := 1.635
const LEG_X := 0.115

var _team_colour: Color = Color(0.29, 0.71, 0.94)
var _downed: bool = false
var _visor: MeshInstance3D = null
var _accent_parts: Array[MeshInstance3D] = []


func build(team_colour: Color) -> void:
	_team_colour = _readable_accent(team_colour)
	ModelKit.clear(self)
	_accent_parts.clear()

	_build_legs()
	_build_torso()
	_build_backpack()
	_build_arms()
	_build_head()


# --------------------------------------------------------------------------

func _build_legs() -> void:
	for side in [-1.0, 1.0]:
		var x: float = side * LEG_X

		# Boot: a sole, a raised toe box and an ankle cuff. The toe is what
		# makes a foot read as a foot from above, which is the angle a
		# teammate standing next to you actually sees.
		_part(MeshFactory.beveled_box(Vector3(0.155, 0.055, 0.30), 0.02),
			Vector3(x, 0.028, -0.03), HARD)
		_part(MeshFactory.beveled_box(Vector3(0.145, 0.085, 0.20), 0.025),
			Vector3(x, 0.095, -0.055), HARD_LIGHT)
		_part(MeshFactory.beveled_box(Vector3(0.135, 0.10, 0.16), 0.03),
			Vector3(x, 0.16, 0.005), HARD)
		_part(MeshFactory.torus(0.075, 0.022, 10, 5), Vector3(x, 0.225, 0.0), TRIM)

		# Shin, knee, thigh. The knee sphere is slightly proud of both capsules
		# so the joint reads even when the leg is straight.
		_part(MeshFactory.capsule(0.34, 0.072, 8), Vector3(x, 0.40, 0.0), SUIT)
		_accent(MeshFactory.sphere(0.082, 5, 8, Vector3(1.0, 0.9, 1.05)),
			Vector3(x, 0.575, -0.01))
		_part(MeshFactory.capsule(0.36, 0.088, 8), Vector3(x, 0.75, 0.0), SUIT)
		# A soft crease at the top of the thigh, where a real suit gathers.
		_part(MeshFactory.torus(0.084, 0.026, 10, 5), Vector3(x, 0.905, 0.0), SUIT_SHADE)


func _build_torso() -> void:
	# Hips, waist, chest. Three pieces with different widths, because a single
	# box from hip to collar is the thing that makes a figure read as a fridge.
	_part(MeshFactory.beveled_box(Vector3(0.36, 0.17, 0.25), 0.05),
		Vector3(0.0, HIP_Y, 0.0), HARD_LIGHT)
	_part(MeshFactory.capsule(0.20, 0.145, 10), Vector3(0.0, HIP_Y + 0.115, 0.0),
		SUIT_SHADE)
	_part(MeshFactory.beveled_box(Vector3(0.44, 0.36, 0.28), 0.07),
		Vector3(0.0, CHEST_Y, 0.0), SUIT)
	# Collar yoke, tying the chest to the neck ring.
	_part(MeshFactory.beveled_box(Vector3(0.34, 0.09, 0.24), 0.04),
		Vector3(0.0, 1.475, 0.0), HARD_LIGHT)

	# The chest control module. A recessed dark box with a lit readout and two
	# switch blocks - the one place on the suit that says "this is equipment".
	_part(MeshFactory.beveled_box(Vector3(0.24, 0.19, 0.055), 0.015),
		Vector3(0.0, 1.29, -0.155), HARD)
	_emissive(MeshFactory.beveled_box(Vector3(0.16, 0.065, 0.02), 0.006),
		Vector3(0.0, 1.325, -0.185), Color(0.45, 0.95, 0.75), 1.1)
	for offset in [-0.055, 0.0, 0.055]:
		_part(MeshFactory.beveled_box(Vector3(0.032, 0.032, 0.02), 0.008),
			Vector3(offset, 1.255, -0.185), TRIM)

	# Team colour goes on a harness: two straps over the shoulders down to a
	# waist belt. Two stacked horizontal bands - the first attempt - read as
	# shelves bolted to the front of the suit; straps read as worn equipment,
	# and they carry the colour vertically where a body is tallest.
	for side in [-1.0, 1.0]:
		_accent(MeshFactory.beveled_box(Vector3(0.075, 0.40, 0.055), 0.015),
			Vector3(side * 0.135, 1.28, -0.148), Vector3(0.0, 0.0, side * 4.0))
		_accent(MeshFactory.beveled_box(Vector3(0.075, 0.36, 0.055), 0.015),
			Vector3(side * 0.125, 1.30, 0.145), Vector3(0.0, 0.0, side * 4.0))
		# Over the shoulder, joining front to back.
		_accent(MeshFactory.beveled_box(Vector3(0.075, 0.05, 0.30), 0.015),
			Vector3(side * 0.13, 1.475, 0.0))
	_accent(MeshFactory.beveled_box(Vector3(0.365, 0.065, 0.255), 0.018),
		Vector3(0.0, HIP_Y + 0.015, 0.0))
	# Hip tool clips, so the waist is not bare.
	for side in [-1.0, 1.0]:
		_part(MeshFactory.beveled_box(Vector3(0.05, 0.11, 0.07), 0.015),
			Vector3(side * 0.195, HIP_Y - 0.01, 0.0), HARD)


func _build_backpack() -> void:
	# Life support. Two tubes with open ends and a valve block on top: the
	# silhouette cue that says "spacesuit" from behind, which is how you will
	# usually see a teammate.
	_part(MeshFactory.beveled_box(Vector3(0.34, 0.40, 0.16), 0.04),
		Vector3(0.0, CHEST_Y + 0.01, 0.205), HARD_LIGHT)
	for side in [-1.0, 1.0]:
		_part(MeshFactory.tube(0.34, 0.058, 0.038, 10),
			Vector3(side * 0.095, CHEST_Y + 0.01, 0.295), SUIT)
		_part(MeshFactory.torus(0.06, 0.016, 10, 5),
			Vector3(side * 0.095, CHEST_Y + 0.175, 0.295), TRIM)
	_part(MeshFactory.beveled_box(Vector3(0.30, 0.06, 0.13), 0.02),
		Vector3(0.0, CHEST_Y + 0.235, 0.215), HARD)
	_accent(MeshFactory.beveled_box(Vector3(0.345, 0.05, 0.165), 0.015),
		Vector3(0.0, CHEST_Y - 0.145, 0.205))
	# The hose that any real suit has looping from pack to chest.
	for side in [-1.0, 1.0]:
		_part(MeshFactory.capsule(0.30, 0.021, 6),
			Vector3(side * 0.185, CHEST_Y + 0.06, 0.10), HARD,
			Vector3(0.0, 0.0, side * 26.0))


func _build_arms() -> void:
	for side in [-1.0, 1.0]:
		var x: float = side * SHOULDER_X

		# Shoulder: a sphere inside a hard cap, so the arm has an obvious
		# pivot rather than growing straight out of the chest.
		_part(MeshFactory.sphere(0.088, 5, 9), Vector3(x, SHOULDER_Y, 0.0), SUIT_SHADE)
		_accent(MeshFactory.beveled_box(Vector3(0.13, 0.115, 0.20), 0.04),
			Vector3(x + side * 0.012, SHOULDER_Y + 0.025, 0.0))

		# Upper arm, elbow, forearm. Arms hang slightly away from the body,
		# which is both how a pressurised suit sits and what keeps the
		# silhouette from fusing into one mass.
		_part(MeshFactory.capsule(0.26, 0.062, 8),
			Vector3(x + side * 0.022, SHOULDER_Y - 0.155, 0.0), SUIT,
			Vector3(0.0, 0.0, side * -5.0))
		_part(MeshFactory.sphere(0.068, 5, 8),
			Vector3(x + side * 0.038, SHOULDER_Y - 0.285, 0.0), SUIT_SHADE)
		_part(MeshFactory.capsule(0.24, 0.058, 8),
			Vector3(x + side * 0.048, SHOULDER_Y - 0.405, 0.0), SUIT,
			Vector3(0.0, 0.0, side * -3.0))
		# Cuff, then a glove that is wider than the wrist.
		_part(MeshFactory.torus(0.062, 0.018, 10, 5),
			Vector3(x + side * 0.052, SHOULDER_Y - 0.515, 0.0), TRIM)
		_part(MeshFactory.beveled_box(Vector3(0.085, 0.115, 0.10), 0.03),
			Vector3(x + side * 0.054, SHOULDER_Y - 0.585, -0.005), HARD)


func _build_head() -> void:
	# Neck ring. On a real suit this is the seal between helmet and torso, and
	# it is the single detail that most reliably says "pressure suit".
	_part(MeshFactory.torus(0.093, 0.026, 12, 6), Vector3(0.0, 1.525, 0.0), TRIM)
	_part(MeshFactory.capsule(0.10, 0.062, 8), Vector3(0.0, 1.535, 0.0), SUIT_SHADE)

	# Helmet: a slightly egg-shaped sphere, not a box. Kept small - an oversized
	# helmet is what turns an astronaut into a bobblehead.
	_part(MeshFactory.sphere(0.152, 6, 11, Vector3(1.0, 1.06, 1.04)),
		Vector3(0.0, HELMET_Y, 0.005), SUIT)
	# Team band around the crown, readable from any angle including above.
	_accent(MeshFactory.torus(0.132, 0.022, 14, 6), Vector3(0.0, HELMET_Y + 0.075, 0.005))

	# Visor. A dark bubble pushed out through the FRONT of the helmet rather
	# than sunk into it: an intersecting squashed sphere of similar radius
	# produced a chewed-looking dark band across the face where the two
	# surfaces cut each other at a grazing angle. Smaller, further forward, and
	# it reads as a lens.
	_visor = _part(MeshFactory.sphere(0.117, 5, 11, Vector3(1.06, 0.86, 1.0)),
		Vector3(0.0, HELMET_Y - 0.012, -0.072), VISOR, Vector3.ZERO, 0.15, 0.1)
	# A dim glow from inside, so a teammate in a dark cave still has a face
	# pointed at you. Emission on the glass itself, not a bright bar across it.
	ModelKit.set_emission(_visor, VISOR_GLINT, 0.22)
	(_visor.material_override as StandardMaterial3D).albedo_color = VISOR
	# Seal ring where visor meets helmet. A torus lies in the XZ plane, so it
	# is stood upright to face forward.
	_part(MeshFactory.torus(0.118, 0.016, 16, 6),
		Vector3(0.0, HELMET_Y - 0.012, -0.058), TRIM, Vector3(90.0, 0.0, 0.0))

	# Helmet lamps either side of the brow, and a stub antenna.
	for side in [-1.0, 1.0]:
		_part(MeshFactory.tube(0.05, 0.032, 0.022, 8),
			Vector3(side * 0.105, HELMET_Y + 0.055, -0.055), HARD,
			Vector3(90.0, 0.0, 0.0))
		_emissive(MeshFactory.sphere(0.021, 4, 7),
			Vector3(side * 0.105, HELMET_Y + 0.055, -0.078),
			Color(1.0, 0.95, 0.82), 2.2)
	_part(MeshFactory.capsule(0.13, 0.011, 6),
		Vector3(0.115, HELMET_Y + 0.11, 0.06), HARD, Vector3(-14.0, 0.0, 12.0))


# --------------------------------------------------------------------------

func _part(mesh: Mesh, position: Vector3, colour: Color,
		rotation_degrees_value: Vector3 = Vector3.ZERO,
		metallic: float = 0.25, roughness: float = 0.55) -> MeshInstance3D:
	return ModelKit.part(self, mesh, position, colour, metallic, roughness,
		rotation_degrees_value)


## A part that carries the player's team colour, so a glance tells you who is
## who without reading a nameplate.
func _accent(mesh: Mesh, position: Vector3,
		rotation_degrees_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := ModelKit.part(self, mesh, position, _team_colour, 0.25, 0.5,
		rotation_degrees_value)
	_accent_parts.append(instance)
	return instance


func _emissive(mesh: Mesh, position: Vector3, colour: Color, energy: float) -> MeshInstance3D:
	return ModelKit.emissive(self, mesh, position, colour, energy)


## A pale team colour disappears against a white suit under a bright key light -
## four players all end up looking the same, which defeats the point. Push
## saturation up and value down until the accent is unmistakably a colour.
static func _readable_accent(colour: Color) -> Color:
	return Color.from_hsv(colour.h, minf(colour.s * 1.45 + 0.12, 1.0),
		clampf(colour.v * 0.86, 0.25, 0.92))


## Downed players wash out to a warning colour, which has to be readable across
## a dark jungle clearing.
func set_downed(downed: bool) -> void:
	_downed = downed
	for instance in _accent_parts:
		ModelKit.set_albedo(instance, Color(0.62, 0.16, 0.18) if downed else _team_colour)
	ModelKit.set_emission(_visor, Color(1.0, 0.3, 0.25) if downed else VISOR_GLINT, 0.22)
	# set_emission also sets albedo; the glass must stay dark either way.
	var glass := _visor.material_override as StandardMaterial3D
	if glass != null:
		glass.albedo_color = VISOR
