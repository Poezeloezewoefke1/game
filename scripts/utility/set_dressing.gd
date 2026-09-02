@tool
extends Node3D
class_name SetDressing
## One hand-placed piece of clutter, chosen from a catalogue by name.
##
## WHY A CATALOGUE RATHER THAN MORE SCENES. A crate, a pipe run, a floodlight
## and a barrel are each five to fifteen boxes; authoring one .tscn per kind
## would be thirty files that all say the same thing in scene text, and every
## tweak would mean editing thirty files. One node with a `kind` export means a
## level line is `kind = "crate_stack"` and the geometry lives next to the
## reasoning for it.
##
## This is NOT procedural generation. Every instance in a level is placed by
## hand at a chosen position with a chosen kind; only the small random details
## WITHIN a piece - which way a crate is scuffed, how a cable sags - are seeded,
## and they are seeded deterministically so every player sees the same clutter.

const METAL := Color(0.40, 0.44, 0.52)
const METAL_DARK := Color(0.20, 0.22, 0.28)
const TRIM := Color(0.66, 0.70, 0.77)
const CRATE := Color(0.42, 0.40, 0.36)
const CRATE_ALT := Color(0.34, 0.42, 0.44)
const HAZARD := Color(0.86, 0.62, 0.16)
const RUST := Color(0.44, 0.26, 0.15)
const STONE := Color(0.46, 0.43, 0.38)
const STONE_DARK := Color(0.29, 0.27, 0.25)

@export_enum("crate_stack", "barrel_cluster", "pipe_run", "floodlight", "antenna_mast",
	"cable_spool", "locker_bank", "console_bank", "hazard_barrier", "wreckage",
	"supply_pallet", "vent_stack", "banner", "ruin_pillar", "ruin_rubble",
	"temple_brazier", "carved_stele")
var kind: String = "crate_stack":
	set(value):
		kind = value
		_rebuild()

## Changes the small details within the piece, so two crate stacks side by side
## are not identical.
@export var variant: int = 0:
	set(value):
		variant = value
		_rebuild()

## Set true on anything a player could walk into. Purely decorative pieces stay
## non-solid so they never block a corridor or trap someone against a wall.
@export var solid: bool = false:
	set(value):
		solid = value
		_rebuild()

var _built := false


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_built = true

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) * 7919 + variant

	match kind:
		"crate_stack": _crate_stack(rng)
		"barrel_cluster": _barrel_cluster(rng)
		"pipe_run": _pipe_run(rng)
		"floodlight": _floodlight(rng)
		"antenna_mast": _antenna_mast(rng)
		"cable_spool": _cable_spool(rng)
		"locker_bank": _locker_bank(rng)
		"console_bank": _console_bank(rng)
		"hazard_barrier": _hazard_barrier(rng)
		"wreckage": _wreckage(rng)
		"supply_pallet": _supply_pallet(rng)
		"vent_stack": _vent_stack(rng)
		"banner": _banner(rng)
		"ruin_pillar": _ruin_pillar(rng)
		"ruin_rubble": _ruin_rubble(rng)
		"temple_brazier": _temple_brazier(rng)
		"carved_stele": _carved_stele(rng)

	if solid:
		_add_collision()


## A single box hull around whatever was built. Clutter does not need per-part
## collision - it needs to stop the player walking through it.
func _add_collision() -> void:
	var bounds := AABB()
	var first := true
	for child in get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := mi.mesh.get_aabb()
		box.position += mi.position
		if first:
			bounds = box
			first = false
		else:
			bounds = bounds.merge(box)
	if first:
		return
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = bounds.size
	shape.shape = box_shape
	shape.position = bounds.get_center()
	body.add_child(shape)


func _part(mesh: Mesh, position: Vector3, colour: Color, metallic: float = 0.35,
		roughness: float = 0.6, rotation_degrees_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return ModelKit.part(self, mesh, position, colour, metallic, roughness,
		rotation_degrees_value)


func _glow(mesh: Mesh, position: Vector3, colour: Color, energy: float,
		rotation_degrees_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return ModelKit.emissive(self, mesh, position, colour, energy, rotation_degrees_value)


# --------------------------------------------------------------------------
# Station clutter
# --------------------------------------------------------------------------

func _crate_stack(rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(3, 5)
	var y := 0.0
	for i in count:
		var w: float = rng.randf_range(0.62, 0.86)
		var h: float = rng.randf_range(0.5, 0.68)
		var d: float = rng.randf_range(0.6, 0.84)
		var yaw: float = rng.randf_range(-14.0, 14.0)
		var lean := Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06))
		var colour: Color = CRATE if rng.randf() < 0.6 else CRATE_ALT
		_part(MeshFactory.beveled_box(Vector3(w, h, d), 0.035),
			Vector3(lean.x, y + h * 0.5, lean.z), colour, 0.2, 0.75,
			Vector3(0.0, yaw, 0.0))
		# Corner brackets and a strap, which is what says "crate" rather than
		# "box".
		for sx in [-1.0, 1.0]:
			_part(MeshFactory.beveled_box(Vector3(0.05, h * 0.92, 0.05), 0.012),
				Vector3(lean.x + sx * w * 0.46, y + h * 0.5, lean.z + d * 0.44),
				TRIM, 0.7, 0.35, Vector3(0.0, yaw, 0.0))
		_part(MeshFactory.beveled_box(Vector3(w * 1.02, 0.055, d * 1.02), 0.012),
			Vector3(lean.x, y + h * 0.62, lean.z), METAL_DARK, 0.5, 0.5,
			Vector3(0.0, yaw, 0.0))
		if rng.randf() < 0.45:
			_glow(MeshFactory.beveled_box(Vector3(0.09, 0.05, 0.02), 0.008),
				Vector3(lean.x, y + h * 0.36, lean.z - d * 0.5),
				Color(0.4, 0.95, 0.7), 0.8, Vector3(0.0, yaw, 0.0))
		y += h - 0.02


func _barrel_cluster(rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(2, 4)
	for i in count:
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.4, 0.4)
		var radius: float = rng.randf_range(0.28, 0.55) if count > 1 else 0.0
		var h: float = rng.randf_range(0.85, 1.05)
		var pos := Vector3(cos(angle) * radius, h * 0.5, sin(angle) * radius)
		var tipped: bool = rng.randf() < 0.2
		var rot := Vector3(90.0, rng.randf_range(0.0, 360.0), 0.0) if tipped else Vector3.ZERO
		if tipped:
			pos.y = 0.24
		_part(MeshFactory.tapered_column(h, 0.24, 0.24, 12), pos,
			RUST if rng.randf() < 0.4 else METAL, 0.55, 0.6, rot)
		# Rolling hoops.
		for t in [-0.28, 0.28]:
			var hoop_pos := pos + (Vector3(0.0, h * t, 0.0) if not tipped
				else Vector3(sin(deg_to_rad(rot.y)) * h * t, 0.0, cos(deg_to_rad(rot.y)) * h * t))
			_part(MeshFactory.torus(0.25, 0.028, 14, 5), hoop_pos, METAL_DARK, 0.7, 0.4, rot)
		_part(MeshFactory.tapered_column(0.04, 0.2, 0.2, 12),
			pos + (Vector3(0.0, h * 0.5, 0.0) if not tipped else Vector3.ZERO),
			HAZARD, 0.3, 0.6, rot)


func _pipe_run(rng: RandomNumberGenerator) -> void:
	# A bundle of pipes along +X with brackets and a valve wheel. Pipe runs are
	# the cheapest way to make a corridor look serviced rather than moulded.
	var length: float = rng.randf_range(4.0, 7.0)
	var heights: Array = [0.0, 0.34, 0.62]
	for i in heights.size():
		var radius: float = 0.10 if i != 1 else 0.14
		_part(MeshFactory.tube(length, radius, radius * 0.62, 10),
			Vector3(0.0, float(heights[i]), 0.0),
			METAL if i != 1 else RUST, 0.7, 0.42, Vector3(0.0, 0.0, 90.0))
	var brackets := int(length / 1.8) + 1
	for i in brackets:
		var x: float = -length * 0.5 + length * float(i) / float(maxi(brackets - 1, 1))
		_part(MeshFactory.beveled_box(Vector3(0.08, 0.9, 0.32), 0.02),
			Vector3(x, 0.31, 0.0), METAL_DARK, 0.6, 0.45)
	_part(MeshFactory.torus(0.2, 0.035, 14, 5),
		Vector3(length * 0.18, 0.34, 0.0), TRIM, 0.75, 0.3, Vector3(0.0, 90.0, 0.0))
	_part(MeshFactory.beveled_box(Vector3(0.16, 0.2, 0.2), 0.03),
		Vector3(length * 0.18, 0.34, 0.0), METAL_DARK, 0.6, 0.4)
	_glow(MeshFactory.beveled_box(Vector3(0.05, 0.05, 0.03), 0.01),
		Vector3(length * 0.18, 0.52, -0.11), Color(1.0, 0.5, 0.2), 1.0)


func _floodlight(rng: RandomNumberGenerator) -> void:
	var height: float = rng.randf_range(2.3, 3.1)
	_part(MeshFactory.tapered_column(0.12, 0.42, 0.36, 8), Vector3(0.0, 0.06, 0.0),
		METAL_DARK, 0.5, 0.5)
	_part(MeshFactory.tapered_column(height, 0.09, 0.07, 8),
		Vector3(0.0, height * 0.5, 0.0), METAL, 0.7, 0.35)
	var head_y := height - 0.1
	_part(MeshFactory.beveled_box(Vector3(0.44, 0.3, 0.26), 0.05),
		Vector3(0.0, head_y, -0.12), METAL_DARK, 0.6, 0.4, Vector3(22.0, 0.0, 0.0))
	_part(MeshFactory.torus(0.2, 0.03, 12, 5), Vector3(0.0, head_y - 0.05, -0.24),
		TRIM, 0.7, 0.3, Vector3(112.0, 0.0, 0.0))
	_glow(MeshFactory.beveled_box(Vector3(0.34, 0.2, 0.03), 0.01),
		Vector3(0.0, head_y - 0.06, -0.26), Color(1.0, 0.95, 0.85), 2.2,
		Vector3(22.0, 0.0, 0.0))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, head_y - 0.2, -0.5)
	lamp.light_color = Color(1.0, 0.95, 0.86)
	lamp.light_energy = 2.6
	lamp.omni_range = 13.0
	lamp.omni_attenuation = 0.6
	lamp.shadow_enabled = false
	add_child(lamp)
	# Cable trailing back to the floor.
	_part(MeshFactory.capsule(1.2, 0.03, 6), Vector3(0.16, 0.5, 0.2),
		METAL_DARK, 0.2, 0.8, Vector3(18.0, 0.0, 26.0))


func _antenna_mast(rng: RandomNumberGenerator) -> void:
	var height: float = rng.randf_range(4.5, 6.5)
	_part(MeshFactory.beveled_box(Vector3(0.7, 0.16, 0.7), 0.04),
		Vector3(0.0, 0.08, 0.0), METAL_DARK, 0.5, 0.5)
	for i in 3:
		var angle := TAU * float(i) / 3.0
		_part(MeshFactory.beveled_box(Vector3(0.07, height, 0.07), 0.02),
			Vector3(cos(angle) * 0.16, height * 0.5 + 0.1, sin(angle) * 0.16),
			METAL, 0.7, 0.35)
	# Cross-bracing, which is most of what makes a lattice read as a lattice.
	var rungs := int(height / 0.75)
	for i in rungs:
		var y := 0.4 + float(i) * 0.75
		_part(MeshFactory.torus(0.17, 0.02, 8, 4), Vector3(0.0, y, 0.0),
			METAL_DARK, 0.7, 0.4)
	_part(MeshFactory.tapered_column(0.5, 0.26, 0.05, 8),
		Vector3(0.0, height + 0.35, 0.0), TRIM, 0.75, 0.3)
	_glow(MeshFactory.sphere(0.07, 4, 7), Vector3(0.0, height + 0.68, 0.0),
		Color(1.0, 0.3, 0.25), 2.0)
	# A dish, angled at the sky.
	_part(MeshFactory.tapered_column(0.12, 0.06, 0.5, 10),
		Vector3(0.0, height * 0.72, 0.28), TRIM, 0.6, 0.35, Vector3(-42.0, 0.0, 0.0))


func _cable_spool(rng: RandomNumberGenerator) -> void:
	var radius: float = rng.randf_range(0.5, 0.72)
	for side in [-1.0, 1.0]:
		_part(MeshFactory.tapered_column(0.08, radius, radius, 14),
			Vector3(0.0, radius, side * 0.28), METAL_DARK, 0.5, 0.55,
			Vector3(90.0, 0.0, 0.0))
	_part(MeshFactory.tapered_column(0.54, radius * 0.62, radius * 0.62, 14),
		Vector3(0.0, radius, 0.0), Color(0.16, 0.15, 0.14), 0.1, 0.85,
		Vector3(90.0, 0.0, 0.0))
	# A loose loop of cable spilling onto the floor.
	for i in 5:
		var angle := float(i) * 0.9 + rng.randf_range(-0.2, 0.2)
		_part(MeshFactory.capsule(0.7, 0.035, 6),
			Vector3(cos(angle) * 0.75, 0.05, sin(angle) * 0.75 + 0.4),
			Color(0.14, 0.14, 0.16), 0.1, 0.85,
			Vector3(90.0, rng.randf_range(0.0, 180.0), 0.0))


func _locker_bank(rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(3, 4)
	for i in count:
		var x := (float(i) - float(count - 1) * 0.5) * 0.68
		_part(MeshFactory.beveled_box(Vector3(0.64, 1.85, 0.5), 0.04),
			Vector3(x, 0.95, 0.0), METAL, 0.55, 0.45)
		_part(MeshFactory.beveled_box(Vector3(0.56, 1.6, 0.06), 0.02),
			Vector3(x, 0.98, -0.26), METAL_DARK, 0.5, 0.5)
		_part(MeshFactory.beveled_box(Vector3(0.05, 0.16, 0.04), 0.01),
			Vector3(x + 0.2, 0.98, -0.3), TRIM, 0.8, 0.3)
		# Vent slots near the top of each door.
		for k in 3:
			_part(MeshFactory.beveled_box(Vector3(0.3, 0.025, 0.02), 0.006),
				Vector3(x, 1.55 + float(k) * 0.07, -0.3), METAL_DARK, 0.5, 0.6)
		if rng.randf() < 0.5:
			_glow(MeshFactory.beveled_box(Vector3(0.06, 0.03, 0.02), 0.006),
				Vector3(x - 0.2, 1.35, -0.3), Color(0.4, 0.9, 0.7), 0.9)
	_part(MeshFactory.beveled_box(Vector3(0.68 * float(count) + 0.1, 0.09, 0.58), 0.02),
		Vector3(0.0, 1.94, 0.0), METAL_DARK, 0.6, 0.4)


func _console_bank(rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(2, 3)
	for i in count:
		var x := (float(i) - float(count - 1) * 0.5) * 1.25
		_part(MeshFactory.beveled_box(Vector3(1.1, 0.9, 0.6), 0.05),
			Vector3(x, 0.5, 0.0), METAL_DARK, 0.5, 0.45)
		_part(MeshFactory.beveled_box(Vector3(1.0, 0.06, 0.5), 0.02),
			Vector3(x, 0.96, -0.04), TRIM, 0.6, 0.35, Vector3(-10.0, 0.0, 0.0))
		_part(MeshFactory.beveled_box(Vector3(0.94, 0.55, 0.05), 0.02),
			Vector3(x, 1.32, 0.14), METAL, 0.55, 0.4, Vector3(-16.0, 0.0, 0.0))
		_glow(MeshFactory.beveled_box(Vector3(0.82, 0.42, 0.02), 0.008),
			Vector3(x, 1.32, 0.11), Color(0.35, 0.85, 1.0), 1.1, Vector3(-16.0, 0.0, 0.0))
		for k in 6:
			_glow(MeshFactory.beveled_box(Vector3(0.05, 0.02, 0.02), 0.005),
				Vector3(x - 0.35 + float(k) * 0.14, 0.99, -0.2),
				Color(1.0, 0.6, 0.25) if k % 3 == 0 else Color(0.4, 0.95, 0.7), 0.9,
				Vector3(-10.0, 0.0, 0.0))


func _hazard_barrier(rng: RandomNumberGenerator) -> void:
	var width: float = rng.randf_range(1.6, 2.4)
	for side in [-1.0, 1.0]:
		_part(MeshFactory.beveled_box(Vector3(0.16, 1.0, 0.34), 0.03),
			Vector3(side * width * 0.5, 0.5, 0.0), METAL_DARK, 0.5, 0.5)
		_part(MeshFactory.beveled_box(Vector3(0.4, 0.08, 0.5), 0.02),
			Vector3(side * width * 0.5, 0.04, 0.0), METAL_DARK, 0.5, 0.5)
	var stripes := int(width / 0.28)
	for i in stripes:
		var x := -width * 0.5 + 0.14 + float(i) * 0.28
		_part(MeshFactory.beveled_box(Vector3(0.26, 0.24, 0.07), 0.015),
			Vector3(x, 0.78, 0.0), HAZARD if i % 2 == 0 else Color(0.16, 0.15, 0.14),
			0.2, 0.65)
	_part(MeshFactory.beveled_box(Vector3(width, 0.07, 0.09), 0.02),
		Vector3(0.0, 0.45, 0.0), METAL, 0.6, 0.45)
	_glow(MeshFactory.sphere(0.06, 4, 7), Vector3(-width * 0.5, 1.06, 0.0),
		Color(1.0, 0.45, 0.15), 1.6)
	_glow(MeshFactory.sphere(0.06, 4, 7), Vector3(width * 0.5, 1.06, 0.0),
		Color(1.0, 0.45, 0.15), 1.6)


func _wreckage(rng: RandomNumberGenerator) -> void:
	# Torn hull plating half-buried, with exposed ribs and a sheared strut.
	for i in 4:
		var angle := rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(0.2, 1.3)
		_part(MeshFactory.beveled_box(
			Vector3(rng.randf_range(0.7, 1.7), 0.09, rng.randf_range(0.5, 1.2)), 0.03),
			Vector3(cos(angle) * dist, rng.randf_range(0.05, 0.4), sin(angle) * dist),
			METAL if rng.randf() < 0.5 else RUST, 0.5, 0.7,
			Vector3(rng.randf_range(-40.0, 40.0), rng.randf_range(0.0, 360.0),
				rng.randf_range(-40.0, 40.0)))
	for i in 3:
		_part(MeshFactory.beveled_box(Vector3(0.09, rng.randf_range(0.8, 1.6), 0.09), 0.02),
			Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.3, 0.7),
				rng.randf_range(-0.6, 0.6)),
			METAL_DARK, 0.6, 0.5,
			Vector3(rng.randf_range(-55.0, 55.0), 0.0, rng.randf_range(-55.0, 55.0)))
	_part(MeshFactory.tube(1.4, 0.16, 0.11, 10),
		Vector3(rng.randf_range(-0.5, 0.5), 0.2, rng.randf_range(-0.5, 0.5)),
		RUST, 0.6, 0.6, Vector3(78.0, rng.randf_range(0.0, 180.0), 0.0))
	if rng.randf() < 0.6:
		_glow(MeshFactory.beveled_box(Vector3(0.14, 0.05, 0.05), 0.01),
			Vector3(rng.randf_range(-0.4, 0.4), 0.3, rng.randf_range(-0.4, 0.4)),
			Color(1.0, 0.35, 0.15), 1.2)


func _supply_pallet(rng: RandomNumberGenerator) -> void:
	_part(MeshFactory.beveled_box(Vector3(1.5, 0.12, 1.2), 0.03),
		Vector3(0.0, 0.06, 0.0), Color(0.32, 0.28, 0.22), 0.1, 0.85)
	for i in 3:
		_part(MeshFactory.beveled_box(Vector3(1.5, 0.09, 0.14), 0.02),
			Vector3(0.0, 0.02, -0.45 + float(i) * 0.45), Color(0.26, 0.22, 0.18), 0.1, 0.9)
	var rows := rng.randi_range(2, 3)
	for i in rows:
		for k in 2:
			_part(MeshFactory.beveled_box(Vector3(0.62, 0.34, 0.5), 0.03),
				Vector3(-0.36 + float(k) * 0.72, 0.29 + float(i) * 0.36,
					rng.randf_range(-0.05, 0.05)),
				CRATE_ALT if (i + k) % 2 == 0 else CRATE, 0.2, 0.75,
				Vector3(0.0, rng.randf_range(-6.0, 6.0), 0.0))
	# Shrink wrap: a translucent-looking pale band round the stack.
	_part(MeshFactory.beveled_box(Vector3(1.56, 0.1, 1.12), 0.02),
		Vector3(0.0, 0.29 + float(rows - 1) * 0.36 * 0.5, 0.0),
		Color(0.72, 0.76, 0.78), 0.1, 0.35)


func _vent_stack(rng: RandomNumberGenerator) -> void:
	var height: float = rng.randf_range(1.6, 2.4)
	_part(MeshFactory.beveled_box(Vector3(0.9, 0.7, 0.9), 0.05),
		Vector3(0.0, 0.35, 0.0), METAL_DARK, 0.55, 0.5)
	_part(MeshFactory.tube(height, 0.26, 0.19, 10),
		Vector3(0.0, 0.7 + height * 0.5, 0.0), METAL, 0.7, 0.4)
	_part(MeshFactory.tapered_column(0.16, 0.4, 0.3, 10),
		Vector3(0.0, 0.7 + height + 0.05, 0.0), METAL_DARK, 0.7, 0.4)
	for i in 4:
		_part(MeshFactory.beveled_box(Vector3(0.82, 0.04, 0.06), 0.01),
			Vector3(0.0, 0.16 + float(i) * 0.13, -0.46), METAL, 0.6, 0.5)
	_glow(MeshFactory.torus(0.24, 0.02, 12, 5), Vector3(0.0, 0.86, 0.0),
		Color(0.35, 0.85, 1.0), 0.9)


func _banner(rng: RandomNumberGenerator) -> void:
	var height: float = rng.randf_range(2.4, 3.2)
	_part(MeshFactory.beveled_box(Vector3(1.0, 0.07, 0.07), 0.015),
		Vector3(0.0, height, 0.0), TRIM, 0.7, 0.3)
	_part(MeshFactory.beveled_box(Vector3(0.86, height * 0.72, 0.02), 0.008),
		Vector3(0.0, height - height * 0.36 - 0.06, 0.0),
		Color(0.16, 0.24, 0.38), 0.0, 0.9)
	_glow(MeshFactory.beveled_box(Vector3(0.5, 0.5, 0.01), 0.005),
		Vector3(0.0, height - 0.55, -0.02), Color(0.35, 0.8, 1.0), 0.75)
	_glow(MeshFactory.beveled_box(Vector3(0.62, 0.05, 0.01), 0.004),
		Vector3(0.0, height - 1.25, -0.02), Color(0.35, 0.8, 1.0), 0.6)


# --------------------------------------------------------------------------
# Temple and canyon dressing
# --------------------------------------------------------------------------

func _ruin_pillar(rng: RandomNumberGenerator) -> void:
	# A broken column: intact drums at the bottom, a sheared top, and the piece
	# that fell off lying alongside.
	var drums := rng.randi_range(2, 4)
	var y := 0.0
	for i in drums:
		var h: float = rng.randf_range(0.5, 0.8)
		var r: float = 0.42 - float(i) * 0.02
		_part(MeshFactory.tapered_column(h, r, r * 0.97, 8),
			Vector3(rng.randf_range(-0.04, 0.04), y + h * 0.5, rng.randf_range(-0.04, 0.04)),
			STONE if i % 2 == 0 else STONE_DARK, 0.0, 0.95,
			Vector3(0.0, rng.randf_range(0.0, 45.0), 0.0))
		y += h
	# The sheared top: a rock, not a clean cut.
	_part(MeshFactory.rock(Vector3(0.8, 0.36, 0.8), variant * 31 + 5),
		Vector3(0.0, y + 0.14, 0.0), STONE, 0.0, 0.95)
	# The fallen drum.
	_part(MeshFactory.tapered_column(0.72, 0.4, 0.38, 8),
		Vector3(rng.randf_range(0.9, 1.5), 0.4, rng.randf_range(-0.8, 0.8)),
		STONE_DARK, 0.0, 0.95,
		Vector3(90.0, rng.randf_range(0.0, 180.0), rng.randf_range(-8.0, 8.0)))


func _ruin_rubble(rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(5, 8):
		var angle := rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(0.0, 1.4)
		var size := Vector3(rng.randf_range(0.3, 0.9), rng.randf_range(0.15, 0.4),
			rng.randf_range(0.3, 0.8))
		_part(MeshFactory.beveled_box(size, 0.04),
			Vector3(cos(angle) * dist, size.y * 0.4, sin(angle) * dist),
			STONE if rng.randf() < 0.6 else STONE_DARK, 0.0, 0.95,
			Vector3(rng.randf_range(-18.0, 18.0), rng.randf_range(0.0, 360.0),
				rng.randf_range(-18.0, 18.0)))
	for i in rng.randi_range(2, 4):
		var angle2 := rng.randf_range(0.0, TAU)
		_part(MeshFactory.rock(Vector3.ONE * rng.randf_range(0.25, 0.5), variant * 17 + i),
			Vector3(cos(angle2) * rng.randf_range(0.4, 1.5), 0.12,
				sin(angle2) * rng.randf_range(0.4, 1.5)),
			STONE_DARK, 0.0, 0.96)


func _temple_brazier(rng: RandomNumberGenerator) -> void:
	_part(MeshFactory.tapered_column(0.16, 0.44, 0.38, 8), Vector3(0.0, 0.08, 0.0),
		STONE_DARK, 0.0, 0.95)
	_part(MeshFactory.tapered_column(0.95, 0.16, 0.13, 6), Vector3(0.0, 0.62, 0.0),
		STONE, 0.0, 0.94)
	_part(MeshFactory.tapered_column(0.3, 0.22, 0.46, 8), Vector3(0.0, 1.22, 0.0),
		STONE, 0.0, 0.92)
	_part(MeshFactory.torus(0.45, 0.05, 14, 6), Vector3(0.0, 1.34, 0.0),
		STONE_DARK, 0.0, 0.94)
	# Embers, not a flame: a flat glowing disc with a few shards over it reads
	# far better in a stylised scene than any attempt at fire geometry.
	_glow(MeshFactory.tapered_column(0.06, 0.34, 0.34, 10), Vector3(0.0, 1.38, 0.0),
		Color(1.0, 0.52, 0.18), 1.5)
	for i in 4:
		var angle := TAU * float(i) / 4.0 + rng.randf_range(-0.3, 0.3)
		_glow(MeshFactory.crystal(0.22, 0.06, 5),
			Vector3(cos(angle) * 0.14, 1.48, sin(angle) * 0.14),
			Color(1.0, 0.62, 0.22), 1.2,
			Vector3(rng.randf_range(-18.0, 18.0), 0.0, rng.randf_range(-18.0, 18.0)))
	var fire := OmniLight3D.new()
	fire.position = Vector3(0.0, 1.5, 0.0)
	fire.light_color = Color(1.0, 0.55, 0.22)
	fire.light_energy = 2.2
	fire.omni_range = 11.0
	fire.omni_attenuation = 0.6
	add_child(fire)


func _carved_stele(rng: RandomNumberGenerator) -> void:
	var height: float = rng.randf_range(2.2, 3.0)
	_part(MeshFactory.beveled_box(Vector3(1.0, 0.2, 0.55), 0.05),
		Vector3(0.0, 0.1, 0.0), STONE_DARK, 0.0, 0.95)
	_part(MeshFactory.beveled_box(Vector3(0.8, height, 0.34), 0.06),
		Vector3(0.0, 0.2 + height * 0.5, 0.0), STONE, 0.0, 0.94,
		Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-6.0, 6.0), 0.0))
	# Rows of glyphs cut into the face. Individually meaningless, collectively
	# the thing that says someone wrote this.
	var rows := int(height / 0.34)
	for i in rows:
		var count := rng.randi_range(2, 4)
		for k in count:
			_glow(MeshFactory.beveled_box(
				Vector3(rng.randf_range(0.07, 0.16), 0.05, 0.02), 0.005),
				Vector3(-0.24 + float(k) * 0.17, 0.5 + float(i) * 0.32, -0.18),
				Color(0.42, 0.72, 1.0), 0.55)
	_part(MeshFactory.wedge(Vector3(0.86, 0.22, 0.4), 0.35),
		Vector3(0.0, 0.2 + height + 0.1, 0.0), STONE_DARK, 0.0, 0.94,
		Vector3(-90.0, 0.0, 0.0))
