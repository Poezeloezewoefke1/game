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
const GOLD := Color(0.78, 0.62, 0.30)
const GOLD_DARK := Color(0.45, 0.34, 0.16)


## A temple pedestal: a stepped stone base, a fluted column and a cradle for
## the crystal. Everything is octagonal rather than square, which is what makes
## it read as carved masonry instead of stacked crates.
static func build_pedestal(root: Node3D, socket: MeshInstance3D, accent: Color) -> void:
	socket.mesh = MeshFactory.tapered_column(0.95, 0.34, 0.27, 8)
	socket.position = Vector3(0.0, 0.78, 0.0)
	ModelKit.set_albedo(socket, STONE)

	# Three steps, each narrower than the one below. Odd numbers of steps look
	# deliberate; two look unfinished.
	ModelKit.part(root, MeshFactory.tapered_column(0.16, 0.82, 0.76, 8),
		Vector3(0.0, 0.08, 0.0), STONE_DARK, 0.05, 0.92)
	ModelKit.part(root, MeshFactory.tapered_column(0.13, 0.68, 0.62, 8),
		Vector3(0.0, 0.225, 0.0), STONE, 0.05, 0.9)
	ModelKit.part(root, MeshFactory.tapered_column(0.11, 0.54, 0.46, 8),
		Vector3(0.0, 0.35, 0.0), STONE_DARK, 0.05, 0.9)

	# Flutes down the column, and buttresses that actually touch both the base
	# and the shaft rather than floating alongside it.
	for i in 8:
		var angle := TAU * float(i) / 8.0
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.05, 0.86, 0.09), 0.02),
			Vector3(cos(angle) * 0.29, 0.78, sin(angle) * 0.29), STONE_DARK, 0.05, 0.9,
			Vector3(0.0, -rad_to_deg(angle), 0.0))
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		var bx := cos(angle)
		var bz := sin(angle)
		# Corbels: two stepped blocks leaning out of the shaft. The first
		# attempt used a wedge, which from most angles is a flat card.
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.15, 0.3, 0.15), 0.04),
			Vector3(bx * 0.34, 0.56, bz * 0.34), STONE, 0.05, 0.9,
			Vector3(0.0, -rad_to_deg(angle), 0.0))
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.19, 0.12, 0.19), 0.04),
			Vector3(bx * 0.4, 0.74, bz * 0.4), STONE_DARK, 0.05, 0.9,
			Vector3(0.0, -rad_to_deg(angle), 0.0))

	# The cradle: a bowl that widens upward, with a lip. A crystal set into a
	# hollow reads as placed; a crystal balanced on a flat top reads as dropped.
	ModelKit.part(root, MeshFactory.tapered_column(0.18, 0.3, 0.46, 8),
		Vector3(0.0, 1.33, 0.0), STONE, 0.05, 0.85)
	ModelKit.part(root, MeshFactory.torus(0.45, 0.05, 16, 6),
		Vector3(0.0, 1.42, 0.0), STONE_DARK, 0.05, 0.88)
	ModelKit.part(root, MeshFactory.tapered_column(0.06, 0.34, 0.3, 8),
		Vector3(0.0, 1.44, 0.0), STONE_DARK, 0.05, 0.9)

	# Which crystal belongs here, legible from across the clearing before you
	# are carrying anything: an inlaid ring plus four studs on the base.
	ModelKit.emissive(root, MeshFactory.torus(0.4, 0.028, 16, 6),
		Vector3(0.0, 1.325, 0.0), accent, 0.85)
	ModelKit.emissive(root, MeshFactory.torus(0.5, 0.022, 16, 5),
		Vector3(0.0, 0.41, 0.0), accent, 0.6)
	for i in 4:
		var angle := TAU * float(i) / 4.0
		ModelKit.emissive(root, MeshFactory.beveled_box(Vector3(0.07, 0.02, 0.14), 0.008),
			Vector3(cos(angle) * 0.6, 0.42, sin(angle) * 0.6), accent, 0.7,
			Vector3(0.0, -rad_to_deg(angle), 0.0))


## The altar: the temple's centrepiece, where the three crystals go and the
## Star Map appears. It has to look like the most important object in the level
## from across the chamber, so it is built as a tiered dais ringed by lit posts
## rather than as a table.
static func build_altar(root: Node3D, base: MeshInstance3D) -> void:
	base.mesh = MeshFactory.tapered_column(0.55, 1.5, 1.28, 8)
	base.position = Vector3(0.0, 0.28, 0.0)
	ModelKit.set_albedo(base, STONE_DARK)

	# Tiers. Wide and shallow, so the eye is led inward and upward.
	ModelKit.part(root, MeshFactory.tapered_column(0.2, 2.35, 2.2, 8),
		Vector3(0.0, 0.1, 0.0), STONE_DARK, 0.05, 0.92)
	ModelKit.part(root, MeshFactory.tapered_column(0.16, 2.0, 1.85, 8),
		Vector3(0.0, 0.28, 0.0), STONE, 0.05, 0.9)

	# Central plinth with a recessed bowl the Star Map rises out of.
	ModelKit.part(root, MeshFactory.tapered_column(0.75, 1.05, 0.88, 8),
		Vector3(0.0, 0.9, 0.0), STONE, 0.05, 0.85)
	ModelKit.part(root, MeshFactory.torus(0.92, 0.07, 20, 6),
		Vector3(0.0, 1.26, 0.0), STONE_DARK, 0.05, 0.88)
	ModelKit.part(root, MeshFactory.tapered_column(0.12, 0.86, 0.72, 8),
		Vector3(0.0, 1.33, 0.0), TRIM, 0.45, 0.4)

	# A ring of runes around the plinth. Individually tiny, collectively the
	# thing that says "this is old and it does something".
	for i in 16:
		var angle := TAU * float(i) / 16.0
		ModelKit.emissive(root, MeshFactory.beveled_box(Vector3(0.06, 0.02, 0.14), 0.006),
			Vector3(cos(angle) * 1.6, 0.37, sin(angle) * 1.6),
			Color(0.35, 0.62, 1.0), 0.55, Vector3(0.0, -rad_to_deg(angle), 0.0))

	# Four posts, each with a caged crystal at the top. The cage is four thin
	# ribs, so the light spills out in slices as you walk past.
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		var x: float = cos(angle) * 1.82
		var z: float = sin(angle) * 1.82
		ModelKit.part(root, MeshFactory.tapered_column(0.18, 0.42, 0.36, 8),
			Vector3(x, 0.44, z), STONE_DARK, 0.05, 0.9)
		ModelKit.part(root, MeshFactory.tapered_column(1.7, 0.24, 0.19, 6),
			Vector3(x, 1.38, z), STONE, 0.05, 0.9)
		ModelKit.part(root, MeshFactory.tapered_column(0.14, 0.3, 0.24, 8),
			Vector3(x, 2.3, z), STONE, 0.05, 0.88)
		ModelKit.emissive(root, MeshFactory.crystal(0.34, 0.12, 6),
			Vector3(x, 2.53, z), Color(0.4, 0.68, 1.0), 0.9)
		for k in 4:
			var rib := TAU * float(k) / 4.0 + PI * 0.25
			ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.035, 0.4, 0.035), 0.01),
				Vector3(x + cos(rib) * 0.13, 2.53, z + sin(rib) * 0.13),
				TRIM, 0.6, 0.35)
		ModelKit.part(root, MeshFactory.torus(0.14, 0.025, 10, 5),
			Vector3(x, 2.73, z), TRIM, 0.6, 0.35)


## The hub's mission terminal: the object every run starts at, so it needs to
## look like a console you would walk up to and press something on.
static func build_terminal(root: Node3D, case_node: MeshInstance3D,
		screen: MeshInstance3D) -> void:
	case_node.mesh = MeshFactory.beveled_box(Vector3(1.34, 0.95, 0.66), 0.07)
	case_node.position = Vector3(0.0, 0.62, 0.0)
	ModelKit.set_albedo(case_node, METAL_DARK)

	screen.mesh = MeshFactory.beveled_box(Vector3(1.02, 0.6, 0.045), 0.012)
	screen.position = Vector3(0.0, 1.38, -0.235)
	screen.rotation_degrees = Vector3(-22.0, 0.0, 0.0)

	# Plinth on four feet, so the console stands on the deck rather than being
	# sunk into it.
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.5, 0.1, 0.84), 0.03),
		Vector3(0.0, 0.11, 0.0), METAL_DARK, 0.5, 0.45)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			ModelKit.part(root, MeshFactory.tapered_column(0.12, 0.12, 0.09, 6),
				Vector3(sx * 0.6, 0.06, sz * 0.3), TRIM, 0.7, 0.3)

	# Bezel around the screen, and a hood over it. The hood is what stops the
	# display reading as a poster stuck to a box.
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.16, 0.74, 0.09), 0.025),
		Vector3(0.0, 1.375, -0.2), METAL, 0.55, 0.4, Vector3(-22.0, 0.0, 0.0))
	# The hood shares the bezel's tilt and overlaps its top edge, so it reads as
	# part of the same casting. Given its own angle it floated above the screen
	# like a propped-open lid.
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.22, 0.09, 0.42), 0.025),
		Vector3(0.0, 1.7, -0.33), METAL, 0.6, 0.35, Vector3(-22.0, 0.0, 0.0))
	# Status bar along the top of the bezel.
	ModelKit.emissive(root, MeshFactory.beveled_box(Vector3(0.9, 0.035, 0.02), 0.008),
		Vector3(0.0, 1.66, -0.31), Color(0.4, 0.95, 0.8), 1.0,
		Vector3(-22.0, 0.0, 0.0))

	# Keyboard shelf with actual keys. Three rows of small blocks does more for
	# "console" than any amount of panel line detail.
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.06, 0.05, 0.36), 0.015),
		Vector3(0.0, 1.09, -0.34), TRIM, 0.6, 0.35, Vector3(-14.0, 0.0, 0.0))
	for row in 3:
		for column in 7:
			ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.085, 0.022, 0.06), 0.006),
				Vector3(-0.39 + float(column) * 0.13,
					1.121 - float(row) * 0.012,
					-0.44 + float(row) * 0.1),
				METAL_DARK, 0.4, 0.5, Vector3(-14.0, 0.0, 0.0))
	# Two big command buttons to one side of the keys.
	for i in 2:
		ModelKit.emissive(root, MeshFactory.tapered_column(0.03, 0.05, 0.045, 8),
			Vector3(0.46, 1.13 - float(i) * 0.012, -0.44 + float(i) * 0.1),
			Color(1.0, 0.55, 0.3) if i == 0 else Color(0.4, 0.9, 0.75), 0.9,
			Vector3(-14.0, 0.0, 0.0))

	# Cooling louvres down each side of the case.
	for side in [-1.0, 1.0]:
		for i in 4:
			ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.03, 0.05, 0.4), 0.008),
				Vector3(side * 0.68, 0.42 + float(i) * 0.09, 0.02),
				METAL, 0.65, 0.35)
	# Back struts and a cable conduit into the floor.
	# A back panel closing the console off, rather than struts - two poles
	# behind a screen read as antennae from every angle a player stands at.
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.2, 0.72, 0.09), 0.03),
		Vector3(0.0, 1.34, 0.16), METAL_DARK, 0.55, 0.4, Vector3(14.0, 0.0, 0.0))
	ModelKit.part(root, MeshFactory.tube(0.55, 0.075, 0.05, 8),
		Vector3(0.0, 0.3, 0.36), METAL_DARK, 0.6, 0.4, Vector3(24.0, 0.0, 0.0))


## The drop pod: the ship that put you on Nerava and the extraction point you
## have to get back to. It is the first and last thing seen in the mission, so
## it is built as a landed craft - nose, hull, hatch, legs with real shock
## absorbers, engines underneath - rather than as a cone on sticks.
static func build_drop_pod(root: Node3D, hull: MeshInstance3D, ring: MeshInstance3D) -> void:
	hull.mesh = MeshFactory.tapered_column(2.3, 1.42, 1.08, 8)
	hull.position = Vector3(0.0, 1.75, 0.0)
	ModelKit.set_albedo(hull, METAL)

	# Nose: a shoulder, a cap and a beacon mast. A pod that just stops at the
	# top has no front, and this is the object players navigate back to.
	ModelKit.part(root, MeshFactory.tapered_column(0.42, 1.12, 0.72, 8),
		Vector3(0.0, 3.1, 0.0), METAL_DARK, 0.6, 0.35)
	ModelKit.part(root, MeshFactory.sphere(0.72, 4, 8, Vector3(1.0, 0.5, 1.0)),
		Vector3(0.0, 3.3, 0.0), METAL, 0.65, 0.32)
	ModelKit.part(root, MeshFactory.capsule(0.5, 0.055, 6), Vector3(0.0, 3.85, 0.0), TRIM)
	ModelKit.emissive(root, MeshFactory.sphere(0.1, 4, 7), Vector3(0.0, 4.08, 0.0),
		Color(1.0, 0.4, 0.3), 1.4)

	# Hull banding and vertical panel seams, so a 2.3 m tapered drum has scale.
	for y in [1.0, 1.9, 2.75]:
		ModelKit.part(root, MeshFactory.torus(1.34 - (y - 1.0) * 0.09, 0.05, 18, 5),
			Vector3(0.0, y, 0.0), METAL_DARK, 0.7, 0.3)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.06, 2.0, 0.1), 0.02),
			Vector3(cos(angle) * 1.26, 1.8, sin(angle) * 1.26), METAL_DARK, 0.7, 0.3,
			Vector3(0.0, -rad_to_deg(angle), 0.0))

	# Hatch: recessed, framed, with a porthole and a handle. This is the part a
	# player walks up to, so it gets the detail.
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.02, 1.42, 0.12), 0.04),
		Vector3(0.0, 1.72, -1.24), METAL_DARK, 0.5, 0.45)
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.84, 1.24, 0.1), 0.03),
		Vector3(0.0, 1.72, -1.3), METAL, 0.55, 0.4)
	ModelKit.part(root, MeshFactory.tube(0.1, 0.26, 0.19, 10),
		Vector3(0.0, 2.05, -1.36), METAL_DARK, 0.7, 0.3, Vector3(90.0, 0.0, 0.0))
	ModelKit.emissive(root, MeshFactory.tapered_column(0.04, 0.19, 0.19, 10),
		Vector3(0.0, 2.05, -1.38), Color(0.5, 0.85, 1.0), 0.7, Vector3(90.0, 0.0, 0.0))
	ModelKit.part(root, MeshFactory.capsule(0.34, 0.035, 6),
		Vector3(0.26, 1.55, -1.38), TRIM, 0.7, 0.3, Vector3(0.0, 0.0, 90.0))
	# Warning chevrons either side of the hatch.
	for side in [-1.0, 1.0]:
		for i in 3:
			ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.09, 0.06, 0.05), 0.01),
				Vector3(side * 0.62, 1.35 + float(i) * 0.16, -1.3),
				Color(0.9, 0.62, 0.15), 0.3, 0.6)

	# Four legs: an angled strut, a bright piston sleeve and a splayed foot.
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		var x := cos(angle)
		var z := sin(angle)
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.2, 1.55, 0.2), 0.04),
			Vector3(x * 1.55, 0.78, z * 1.55), METAL_DARK, 0.65, 0.35,
			Vector3(z * 17.0, 0.0, -x * 17.0))
		ModelKit.part(root, MeshFactory.tube(0.55, 0.11, 0.075, 8),
			Vector3(x * 1.42, 1.2, z * 1.42), TRIM, 0.8, 0.25,
			Vector3(z * 17.0, 0.0, -x * 17.0))
		# Diagonal brace back to the hull, which is what makes a leg look
		# load-bearing rather than glued on.
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.09, 0.95, 0.09), 0.02),
			Vector3(x * 1.05, 1.42, z * 1.05), METAL, 0.7, 0.3,
			Vector3(z * 52.0, 0.0, -x * 52.0))
		# Foot: a pad on an ankle, with a ground spike.
		ModelKit.part(root, MeshFactory.tapered_column(0.13, 0.42, 0.5, 6),
			Vector3(x * 1.9, 0.11, z * 1.9), METAL_DARK, 0.6, 0.4)
		ModelKit.part(root, MeshFactory.sphere(0.13, 4, 7),
			Vector3(x * 1.86, 0.24, z * 1.86), TRIM, 0.75, 0.3)

	# Engines under the floor pan, and the landing-light ring the pod is known
	# by from a distance.
	for i in 3:
		var angle := TAU * float(i) / 3.0 + PI * 0.5
		ModelKit.part(root, MeshFactory.tube(0.34, 0.3, 0.2, 8),
			Vector3(cos(angle) * 0.62, 0.42, sin(angle) * 0.62), METAL_DARK, 0.7, 0.3)
		ModelKit.emissive(root, MeshFactory.tapered_column(0.07, 0.2, 0.13, 8),
			Vector3(cos(angle) * 0.62, 0.24, sin(angle) * 0.62),
			Color(0.45, 0.7, 1.0), 0.7)

	ring.mesh = MeshFactory.torus(2.05, 0.09, 26, 6)
	ring.position = Vector3(0.0, 0.09, 0.0)


## The Sentinel: a fixed armoured head inside a rotating gyro ring.
##
## The three nodes it is handed are not interchangeable, and the split is what
## makes the model work:
##
##   `core`  keeps a hot emissive material and DOES NOT ROTATE, so anything
##           parented to it is the machine's fixed body - the hull cage, the
##           sensor head, the thruster pods.
##   `shell` is spun about Y every frame by `sentinel.gd`, so its children are
##           the orbiting armature. A continuous ring with plates bolted to it
##           reads as a gyroscope; the previous version hung loose slabs in the
##           air at the same radius and read as debris orbiting a rock.
##   `eye`   is recoloured per state by `sentinel.gd` - calm, chasing, firing,
##           staggered - so it is the one part a player reads for intent.
static func build_sentinel(shell: Node3D, core: MeshInstance3D, eye: MeshInstance3D) -> void:
	# The shell node carries a mesh of its own from the scene. Leaving it in
	# place put a fat ring THROUGH the armour added below; it is a mount point
	# now, not a mesh.
	if shell is MeshInstance3D:
		(shell as MeshInstance3D).mesh = null

	_sentinel_core(core)
	_sentinel_head(core, eye)
	_sentinel_ring(shell)


## The power core and the cage around it. Small and bright: the core is the
## thing you shoot at, so it has to be findable, and a big glowing ball would
## wash out every plate in front of it.
static func _sentinel_core(core: MeshInstance3D) -> void:
	core.mesh = MeshFactory.sphere(0.34, 4, 7)
	core.position = Vector3.ZERO

	# Cage: four ribs over the core, meeting at top and bottom. They leave gaps
	# the core glows through, which is what makes it look contained rather than
	# merely nearby.
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		ModelKit.part(core, MeshFactory.beveled_box(Vector3(0.14, 0.96, 0.2), 0.05),
			Vector3(cos(angle) * 0.36, 0.0, sin(angle) * 0.36), METAL_DARK, 0.7, 0.32,
			Vector3(0.0, -rad_to_deg(angle), 0.0))
	# Caps closing the cage, so the ribs end in something.
	for side in [-1.0, 1.0]:
		ModelKit.part(core, MeshFactory.tapered_column(0.34, 0.46, 0.2, 8),
			Vector3(0.0, side * 0.6, 0.0), METAL, 0.7, 0.3,
			Vector3(0.0 if side > 0.0 else 180.0, 0.0, 0.0))
		ModelKit.part(core, MeshFactory.tube(0.14, 0.15, 0.075, 8),
			Vector3(0.0, side * 0.83, 0.0), METAL_DARK, 0.75, 0.28)

	# Three thruster pods around the waist, angled down. They explain how the
	# thing hovers, and they break the top-to-bottom symmetry.
	for i in 3:
		var angle := TAU * float(i) / 3.0 + PI * 0.5
		var x := cos(angle)
		var z := sin(angle)
		ModelKit.part(core, MeshFactory.tube(0.3, 0.13, 0.085, 8),
			Vector3(x * 0.52, -0.2, z * 0.52), METAL, 0.7, 0.3,
			Vector3(-z * 24.0, 0.0, x * 24.0))
		ModelKit.emissive(core, MeshFactory.tapered_column(0.06, 0.085, 0.05, 8),
			Vector3(x * 0.58, -0.36, z * 0.58), Color(0.45, 0.7, 1.0), 0.9)


## The sensor head. A hooded housing on a short neck, pointing the way the
## Sentinel is facing - which is how a player knows whether it has seen them.
static func _sentinel_head(core: MeshInstance3D, eye: MeshInstance3D) -> void:
	ModelKit.part(core, MeshFactory.tapered_column(0.34, 0.3, 0.24, 8),
		Vector3(0.0, 0.08, -0.5), METAL, 0.7, 0.3, Vector3(90.0, 0.0, 0.0))
	ModelKit.part(core, MeshFactory.tube(0.22, 0.27, 0.19, 10),
		Vector3(0.0, 0.08, -0.76), METAL_DARK, 0.75, 0.28, Vector3(90.0, 0.0, 0.0))
	# Brow hood over the lens, angled down: the single detail that turns a
	# glowing dot into something looking at you.
	ModelKit.part(core, MeshFactory.wedge(Vector3(0.5, 0.16, 0.3), 0.3),
		Vector3(0.0, 0.29, -0.74), METAL, 0.7, 0.3, Vector3(-104.0, 0.0, 0.0))
	# Jaw plate underneath, so the head has a bottom as well as a top.
	ModelKit.part(core, MeshFactory.beveled_box(Vector3(0.4, 0.1, 0.26), 0.03),
		Vector3(0.0, -0.13, -0.72), METAL_DARK, 0.7, 0.32)
	# Two mandible fins either side of the lens.
	for side in [-1.0, 1.0]:
		ModelKit.part(core, MeshFactory.wedge(Vector3(0.08, 0.3, 0.34), 0.15),
			Vector3(side * 0.28, 0.06, -0.72), METAL, 0.7, 0.3,
			Vector3(0.0, side * -14.0, side * 20.0))

	eye.mesh = MeshFactory.sphere(0.155, 4, 9, Vector3(1.0, 0.85, 0.7))
	eye.position = Vector3(0.0, 0.08, -0.87)


## The rotating armature: a continuous ring with armour bolted to it, spoked
## back to the hub. `sentinel.gd` spins this, slowly while staggered.
static func _sentinel_ring(shell: Node3D) -> void:
	ModelKit.part(shell, MeshFactory.torus(1.3, 0.08, 24, 7),
		Vector3.ZERO, METAL_DARK, 0.75, 0.3)

	# Six plates ON the ring. Bolted to something is the whole difference
	# between armour and debris.
	for i in 6:
		var angle := TAU * float(i) / 6.0
		var x := cos(angle)
		var z := sin(angle)
		var yaw := -rad_to_deg(angle)
		ModelKit.part(shell, MeshFactory.beveled_box(Vector3(0.32, 0.28, 0.7), 0.07),
			Vector3(x * 1.3, 0.0, z * 1.3), METAL, 0.68, 0.32,
			Vector3(0.0, yaw, 0.0))
		# An outward fin on each plate, which is what gives the silhouette
		# teeth as it turns.
		# Swept back rather than straight out: a fin that trails reads as
		# something that turns, which is exactly what this ring does.
		ModelKit.part(shell, MeshFactory.wedge(Vector3(0.14, 0.3, 0.46), 0.18),
			Vector3(x * 1.5, 0.0, z * 1.5), METAL_DARK, 0.7, 0.3,
			Vector3(0.0, yaw + 62.0, 90.0))
		# A running light, so the rotation is legible in a dark cave.
		ModelKit.emissive(shell, MeshFactory.sphere(0.05, 3, 6),
			Vector3(x * 1.3, 0.16, z * 1.3), Color(0.5, 0.75, 1.0), 0.9)

	# Three spokes back to the hub.
	for i in 3:
		var angle := TAU * float(i) / 3.0
		ModelKit.part(shell, MeshFactory.beveled_box(Vector3(0.1, 0.09, 0.88), 0.03),
			Vector3(cos(angle) * 0.86, 0.0, sin(angle) * 0.86), METAL, 0.7, 0.3,
			Vector3(0.0, -rad_to_deg(angle) + 90.0, 0.0))


## The Star Map: the artefact the whole mission is for, so it gets to be the
## most ornate object in the game. An armillary - a lit core inside three
## gimbal rings at different angles - rather than the single flat torus it was,
## which read as a glowing doughnut.
##
## `mesh` is the node the owning script spins and bobs, so everything is
## parented to it and the whole armillary turns together.
static func build_star_map(mesh: MeshInstance3D, tint: Color) -> void:
	mesh.mesh = MeshFactory.sphere(0.17, 5, 9)

	# Three rings, each tipped differently. Two would look like a mistake and
	# four would read as a ball of wire.
	var tilts: Array = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(72.0, 0.0, 18.0),
		Vector3(-24.0, 0.0, -78.0),
	]
	var radii: Array = [0.56, 0.47, 0.38]
	for i in 3:
		var ring := ModelKit.part(mesh, MeshFactory.torus(radii[i], 0.035, 22, 6),
			Vector3.ZERO, GOLD, 0.85, 0.22, tilts[i])
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Graduations around each ring: what makes it an instrument rather than
		# a hoop.
		for k in 8:
			var angle := TAU * float(k) / 8.0
			ModelKit.part(ring, MeshFactory.beveled_box(Vector3(0.035, 0.06, 0.035), 0.008),
				Vector3(cos(angle) * float(radii[i]), 0.0, sin(angle) * float(radii[i])),
				GOLD_DARK, 0.8, 0.25, Vector3(0.0, -rad_to_deg(angle), 0.0))
		# One lit node per ring, at a different place on each, so the thing
		# looks like it is tracking something.
		ModelKit.emissive(ring, MeshFactory.sphere(0.045, 3, 7),
			Vector3(cos(float(i) * 2.1) * float(radii[i]), 0.0,
				sin(float(i) * 2.1) * float(radii[i])), tint, 1.1)

	# Polar axis through the core, and caps on it.
	ModelKit.part(mesh, MeshFactory.capsule(1.3, 0.022, 6), Vector3.ZERO, GOLD, 0.85, 0.22)
	for side in [-1.0, 1.0]:
		ModelKit.part(mesh, MeshFactory.tapered_column(0.09, 0.075, 0.03, 6),
			Vector3(0.0, side * 0.68, 0.0), GOLD_DARK, 0.8, 0.25,
			Vector3(0.0 if side > 0.0 else 180.0, 0.0, 0.0))
