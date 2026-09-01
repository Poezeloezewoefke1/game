extends RefCounted
class_name PropBuilder
## Geometry for the world's props, kept out of the scripts that own their rules.
##
## Each interactable scene still declares the nodes its script talks to
## (`Socket`, `PlacedCrystal`, `Beam`...). These functions replace those nodes'
## meshes with real geometry and hang the decorative parts off them, so
## `crystal_pedestal.gd` stays about what a pedestal ACCEPTS rather than what it
## looks like.

const STONE := Color(0.46, 0.43, 0.38)
const STONE_DARK := Color(0.29, 0.27, 0.25)
const METAL := Color(0.34, 0.38, 0.45)
const METAL_DARK := Color(0.17, 0.19, 0.24)
const TRIM := Color(0.62, 0.66, 0.73)


## A temple pedestal: a stepped stone base, a fluted column and a cradle for the
## crystal. Previously a single cone, which read as a traffic cone.
static func build_pedestal(root: Node3D, socket: MeshInstance3D, accent: Color) -> void:
	socket.mesh = MeshFactory.tapered_column(1.15, 0.42, 0.3, 8)
	socket.position = Vector3(0.0, 0.72, 0.0)
	ModelKit.set_albedo(socket, STONE)

	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.3, 0.16, 1.3), 0.04),
		Vector3(0.0, 0.08, 0.0), STONE_DARK, 0.05, 0.9)
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.05, 0.14, 1.05), 0.04),
		Vector3(0.0, 0.22, 0.0), STONE, 0.05, 0.9)
	# Cradle the crystal sits in
	ModelKit.part(root, MeshFactory.tapered_column(0.2, 0.34, 0.44, 8),
		Vector3(0.0, 1.38, 0.0), STONE, 0.05, 0.85)
	# Four buttresses, so the column is not a bare cylinder from every angle
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.12, 0.8, 0.2), 0.03),
			Vector3(cos(angle) * 0.34, 0.7, sin(angle) * 0.34), STONE_DARK, 0.05, 0.9,
			Vector3(0.0, -rad_to_deg(angle), 0.0))
	# An inlaid band in the crystal's colour: which crystal belongs here, legible
	# from across the clearing before you are carrying anything.
	ModelKit.emissive(root, MeshFactory.beveled_box(Vector3(0.95, 0.05, 0.95), 0.02),
		Vector3(0.0, 0.3, 0.0), accent, 0.9)


## The altar: a wide dais with a raised plinth and four corner posts.
static func build_altar(root: Node3D, base: MeshInstance3D) -> void:
	base.mesh = MeshFactory.tapered_column(0.5, 1.55, 1.4, 8)
	base.position = Vector3(0.0, 0.25, 0.0)
	ModelKit.set_albedo(base, STONE_DARK)

	ModelKit.part(root, MeshFactory.beveled_box(Vector3(4.2, 0.18, 4.2), 0.05),
		Vector3(0.0, 0.09, 0.0), STONE_DARK, 0.05, 0.92)
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(3.4, 0.16, 3.4), 0.05),
		Vector3(0.0, 0.26, 0.0), STONE, 0.05, 0.9)
	ModelKit.part(root, MeshFactory.tapered_column(0.9, 1.1, 0.85, 8),
		Vector3(0.0, 0.85, 0.0), STONE, 0.05, 0.85)
	ModelKit.part(root, MeshFactory.tapered_column(0.14, 0.95, 1.0, 8),
		Vector3(0.0, 1.35, 0.0), TRIM, 0.5, 0.4)
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.28, 2.1, 0.28), 0.05),
			Vector3(cos(angle) * 1.85, 1.05, sin(angle) * 1.85), STONE, 0.05, 0.9)
		ModelKit.emissive(root, MeshFactory.beveled_box(Vector3(0.16, 0.16, 0.16), 0.03),
			Vector3(cos(angle) * 1.85, 2.18, sin(angle) * 1.85), Color(0.35, 0.62, 1.0), 1.1)


## The hub's mission terminal: an angled console rather than a slab.
static func build_terminal(root: Node3D, case_node: MeshInstance3D,
		screen: MeshInstance3D) -> void:
	case_node.mesh = MeshFactory.beveled_box(Vector3(1.5, 1.05, 0.75), 0.06)
	case_node.position = Vector3(0.0, 0.55, 0.0)
	ModelKit.set_albedo(case_node, METAL_DARK)

	screen.mesh = MeshFactory.beveled_box(Vector3(1.2, 0.72, 0.07), 0.02)
	screen.position = Vector3(0.0, 1.32, -0.2)
	screen.rotation_degrees = Vector3(-18.0, 0.0, 0.0)

	# Plinth and hood
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.7, 0.12, 0.95), 0.04),
		Vector3(0.0, 0.06, 0.0), METAL_DARK, 0.5, 0.45)
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.35, 0.85, 0.12), 0.03),
		Vector3(0.0, 1.36, 0.16), METAL, 0.55, 0.4, Vector3(-18.0, 0.0, 0.0))
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.4, 0.1, 0.5), 0.03),
		Vector3(0.0, 1.78, 0.02), METAL, 0.6, 0.35)
	# Angled keyboard shelf
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.15, 0.06, 0.4), 0.02),
		Vector3(0.0, 1.02, -0.35), TRIM, 0.6, 0.35, Vector3(-12.0, 0.0, 0.0))
	# Side struts
	for side in [-1.0, 1.0]:
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.1, 1.7, 0.1), 0.02),
			Vector3(side * 0.78, 0.9, 0.16), TRIM, 0.7, 0.3)


## The drop pod: a landed capsule on splayed legs.
static func build_drop_pod(root: Node3D, hull: MeshInstance3D, ring: MeshInstance3D) -> void:
	hull.mesh = MeshFactory.tapered_column(2.6, 1.45, 0.95, 8)
	hull.position = Vector3(0.0, 1.6, 0.0)
	ModelKit.set_albedo(hull, METAL)

	ModelKit.part(root, MeshFactory.tapered_column(0.5, 1.0, 1.4, 8),
		Vector3(0.0, 3.1, 0.0), METAL_DARK, 0.6, 0.35)
	ModelKit.part(root, MeshFactory.tapered_column(0.35, 1.5, 1.15, 8),
		Vector3(0.0, 0.35, 0.0), METAL_DARK, 0.6, 0.35)
	# Hatch
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.0, 1.3, 0.14), 0.04),
		Vector3(0.0, 1.7, -1.15), METAL_DARK, 0.5, 0.45)
	# Landing legs and feet
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		var x := cos(angle)
		var z := sin(angle)
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.16, 1.5, 0.16), 0.03),
			Vector3(x * 1.5, 0.72, z * 1.5), TRIM, 0.7, 0.3,
			Vector3(z * 16.0, 0.0, -x * 16.0))
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.5, 0.12, 0.5), 0.03),
			Vector3(x * 1.85, 0.06, z * 1.85), METAL_DARK, 0.6, 0.4)
	ring.mesh = MeshFactory.tapered_column(0.1, 2.15, 2.15, 16)
	ring.position = Vector3(0.0, 0.05, 0.0)


## The Sentinel: an armoured core inside a broken ring, rather than a ball.
static func build_sentinel(shell: Node3D, core: MeshInstance3D, eye: MeshInstance3D) -> void:
	# The shell node carries its own torus from the scene. Leaving it in place
	# put a single fat ring THROUGH the armour segments added below - clear it,
	# it is a mount point now, not a mesh.
	if shell is MeshInstance3D:
		(shell as MeshInstance3D).mesh = null
	core.mesh = MeshFactory.rock(Vector3(1.25, 1.25, 1.25), 4, 4, 8)
	eye.mesh = MeshFactory.beveled_box(Vector3(0.62, 0.26, 0.2), 0.05)
	eye.position = Vector3(0.0, 0.12, -0.88)

	# Armour segments around the core, with a deliberate gap so the silhouette
	# is not a perfect circle from any angle.
	for i in 7:
		var angle := TAU * float(i) / 8.0
		ModelKit.part(shell, MeshFactory.beveled_box(Vector3(0.5, 0.34, 1.0), 0.06),
			Vector3(cos(angle) * 1.5, 0.0, sin(angle) * 1.5), METAL, 0.65, 0.35,
			Vector3(0.0, -rad_to_deg(angle), 0.0))
	# Spines above and below, so it reads as a machine and not a wheel
	for side in [-1.0, 1.0]:
		ModelKit.part(shell, MeshFactory.beveled_box(Vector3(0.22, 0.7, 0.22), 0.04),
			Vector3(0.0, side * 1.15, 0.0), METAL_DARK, 0.6, 0.4)
