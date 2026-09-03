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


# ==========================================================================
# The Starfarer
# ==========================================================================

const SEAT_FRAME := Color(0.30, 0.33, 0.40)
const SEAT_PAD := Color(0.24, 0.30, 0.38)
const HULL_TRIM := Color(0.66, 0.70, 0.78)


## A flight seat: pedestal, bucket, high back and a restraint harness.
##
## The harness is the load-bearing detail. A chair without one reads as office
## furniture; two straps over the shoulders say "this vehicle accelerates hard
## enough that you have to be held down", which is the whole reason the crew has
## to sit before launch.
static func build_crew_seat(root: Node3D, frame: MeshInstance3D,
		cushion: MeshInstance3D) -> void:
	frame.mesh = MeshFactory.beveled_box(Vector3(0.78, 0.16, 0.78), 0.04)
	frame.position = Vector3(0.0, 0.46, 0.0)
	ModelKit.set_albedo(frame, SEAT_FRAME)

	cushion.mesh = MeshFactory.beveled_box(Vector3(0.70, 0.14, 0.70), 0.06)
	cushion.position = Vector3(0.0, 0.60, 0.0)
	ModelKit.set_albedo(cushion, SEAT_PAD)

	# Pedestal and floor plate.
	ModelKit.part(root, MeshFactory.tapered_column(0.40, 0.20, 0.13, 8),
		Vector3(0.0, 0.20, 0.0), METAL_DARK, 0.7, 0.35)
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.66, 0.06, 0.66), 0.02),
		Vector3(0.0, 0.03, 0.0), METAL, 0.75, 0.32)

	# Back and headrest, raked back a little.
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.70, 0.86, 0.14), 0.05),
		Vector3(0.0, 1.06, 0.32), SEAT_PAD, 0.1, 0.75, Vector3(9.0, 0.0, 0.0))
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.42, 0.22, 0.13), 0.05),
		Vector3(0.0, 1.53, 0.24), SEAT_FRAME, 0.2, 0.6, Vector3(9.0, 0.0, 0.0))

	# Arm rests.
	for sx in [-1.0, 1.0]:
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.10, 0.09, 0.52), 0.03),
			Vector3(sx * 0.40, 0.86, -0.02), SEAT_FRAME, 0.5, 0.45)
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.08, 0.24, 0.08), 0.02),
			Vector3(sx * 0.40, 0.72, 0.16), METAL, 0.7, 0.35)

	# Five-point harness: two shoulder straps crossing to a central buckle.
	for sx in [-1.0, 1.0]:
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.09, 0.72, 0.04), 0.012),
			Vector3(sx * 0.17, 1.06, 0.20), Color(0.20, 0.22, 0.26), 0.0, 0.9,
			Vector3(9.0, 0.0, sx * 11.0))
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.14, 0.11, 0.06), 0.02),
		Vector3(0.0, 0.76, 0.06), HULL_TRIM, 0.8, 0.3)


## The four pre-flight stations. One housing, one big status panel, and a lever
## or valve so each station looks like a thing you operate rather than a screen
## you look at.
static func build_ship_station(root: Node3D, housing: MeshInstance3D,
		panel: MeshInstance3D) -> void:
	housing.mesh = MeshFactory.beveled_box(Vector3(1.10, 1.40, 0.46), 0.05)
	housing.position = Vector3(0.0, 0.70, 0.0)
	ModelKit.set_albedo(housing, METAL_DARK)

	panel.mesh = MeshFactory.beveled_box(Vector3(0.78, 0.44, 0.04), 0.015)
	panel.position = Vector3(0.0, 1.12, -0.24)
	panel.rotation_degrees = Vector3(-16.0, 0.0, 0.0)

	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.20, 0.10, 0.56), 0.03),
		Vector3(0.0, 0.05, 0.0), METAL, 0.7, 0.38)
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.90, 0.56, 0.10), 0.02),
		Vector3(0.0, 1.12, -0.20), METAL, 0.6, 0.4, Vector3(-16.0, 0.0, 0.0))
	# A wheel valve and three toggles. Something to put your hands on.
	ModelKit.part(root, MeshFactory.torus(0.19, 0.035, 12, 6),
		Vector3(0.0, 0.52, -0.26), HULL_TRIM, 0.8, 0.3, Vector3(90.0, 0.0, 0.0))
	ModelKit.part(root, MeshFactory.tube(0.10, 0.05, 0.03, 8),
		Vector3(0.0, 0.52, -0.24), METAL, 0.8, 0.3, Vector3(90.0, 0.0, 0.0))
	for i in 3:
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.05, 0.14, 0.05), 0.012),
			Vector3(-0.36 + i * 0.12, 0.82, -0.26), HULL_TRIM, 0.7, 0.35,
			Vector3(-24.0, 0.0, 0.0))


## The chart table. A low plinth with a projected volume standing above it - the
## hologram mesh is what the destination shader is applied to.
static func build_nav_console(root: Node3D, table: MeshInstance3D,
		hologram: MeshInstance3D) -> void:
	table.mesh = MeshFactory.beveled_box(Vector3(2.10, 0.18, 1.40), 0.05)
	table.position = Vector3(0.0, 0.92, 0.0)
	ModelKit.set_albedo(table, METAL_DARK)

	# A sphere rather than a box: the thing being projected is a WORLD.
	hologram.mesh = MeshFactory.sphere(0.42, 8, 14)
	hologram.position = Vector3(0.0, 1.62, 0.0)

	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.90, 0.80, 1.20), 0.06),
		Vector3(0.0, 0.44, 0.0), METAL, 0.6, 0.42)
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(2.16, 0.05, 1.46), 0.02),
		Vector3(0.0, 1.02, 0.0), HULL_TRIM, 0.7, 0.3)
	# Emitter ring in the table top, and a rail of controls along the near edge.
	ModelKit.emissive(root, MeshFactory.torus(0.50, 0.035, 16, 6),
		Vector3(0.0, 1.05, 0.0), Color(0.35, 0.85, 1.0), 1.2,
		Vector3(90.0, 0.0, 0.0))
	for i in 5:
		ModelKit.emissive(root, MeshFactory.beveled_box(Vector3(0.07, 0.02, 0.05), 0.006),
			Vector3(-0.36 + i * 0.18, 1.06, -0.56), Color(0.4, 0.9, 1.0), 0.9)
	for sx in [-1.0, 1.0]:
		ModelKit.part(root, MeshFactory.tapered_column(0.44, 0.14, 0.10, 6),
			Vector3(sx * 0.78, 0.22, 0.0), METAL_DARK, 0.7, 0.35)


## The launch lever: a floor-mounted throttle in a cage, with a status lamp.
static func build_launch_lever(root: Node3D, housing: MeshInstance3D,
		handle: MeshInstance3D) -> void:
	housing.mesh = MeshFactory.beveled_box(Vector3(0.80, 1.00, 0.60), 0.05)
	housing.position = Vector3(0.0, 0.50, 0.0)
	ModelKit.set_albedo(housing, METAL_DARK)

	handle.mesh = MeshFactory.beveled_box(Vector3(0.12, 0.66, 0.12), 0.03)
	handle.position = Vector3(0.0, 1.32, -0.10)
	handle.rotation_degrees = Vector3(-18.0, 0.0, 0.0)

	ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.94, 0.09, 0.72), 0.03),
		Vector3(0.0, 0.045, 0.0), METAL, 0.75, 0.35)
	# Slot the lever travels in, and the guard rails either side of it.
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.16, 0.05, 0.44), 0.012),
		Vector3(0.0, 1.02, -0.02), Color(0.10, 0.11, 0.14), 0.4, 0.6)
	for sx in [-1.0, 1.0]:
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.06, 0.54, 0.06), 0.02),
			Vector3(sx * 0.28, 1.24, -0.06), HULL_TRIM, 0.8, 0.3)
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.62, 0.06, 0.06), 0.02),
		Vector3(0.0, 1.50, -0.06), HULL_TRIM, 0.8, 0.3)
	# Grip on top of the lever.
	ModelKit.part(root, MeshFactory.sphere(0.10, 5, 8),
		Vector3(0.0, 1.62, -0.20), Color(0.72, 0.24, 0.20), 0.2, 0.6)
	# Hazard stripes on the housing front.
	for i in 3:
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.13, 0.34, 0.02), 0.006),
			Vector3(-0.24 + i * 0.24, 0.34, -0.31), Color(0.86, 0.62, 0.16), 0.2, 0.7,
			Vector3(0.0, 0.0, 22.0))


## The Warden. Bigger than the Sentinel and built to read at a distance: a heavy
## faceted core, a hooded eye, four buttressed arms, and three shield nodes on a
## ring around it. The nodes carry their own colliders so a shot can be told
## from a shot at the body - that distinction is the whole shield phase.
static func build_warden(root: Node3D, hull: MeshInstance3D, eye: MeshInstance3D,
		shield: MeshInstance3D, ring: Node3D) -> void:
	hull.mesh = MeshFactory.rock(Vector3(3.4, 2.6, 3.4), 41, 4, 9)
	hull.position = Vector3.ZERO
	ModelKit.set_albedo(hull, Color(0.24, 0.25, 0.30))

	# Buttresses, angled down and out, so the silhouette is not a ball.
	for i in 4:
		var a := deg_to_rad(45.0 + i * 90.0)
		ModelKit.part(root, MeshFactory.wedge(Vector3(0.9, 0.7, 2.4), 0.45),
			Vector3(sin(a) * 1.9, -0.5, cos(a) * 1.9), Color(0.18, 0.19, 0.23),
			0.65, 0.42, Vector3(18.0, rad_to_deg(a), 0.0))
		ModelKit.emissive(root, MeshFactory.beveled_box(Vector3(0.12, 0.12, 1.5), 0.03),
			Vector3(sin(a) * 1.85, -0.42, cos(a) * 1.85), Color(0.4, 0.8, 1.0), 1.1,
			Vector3(18.0, rad_to_deg(a), 0.0))

	# A hood over the eye. Without it the eye reads as a light bulb.
	ModelKit.part(root, MeshFactory.wedge(Vector3(1.9, 0.8, 1.3), 0.3),
		Vector3(0.0, 0.95, -1.25), Color(0.16, 0.17, 0.21), 0.6, 0.4,
		Vector3(-26.0, 0.0, 0.0))
	eye.mesh = MeshFactory.sphere(0.44, 6, 10)
	eye.position = Vector3(0.0, 0.42, -1.55)

	# The shield itself: a shell around everything, hidden once it is down.
	shield.mesh = MeshFactory.sphere(3.6, 8, 14)
	shield.position = Vector3.ZERO

	# Three nodes on a ring, each its own body so it can be shot individually.
	for i in 3:
		var a := deg_to_rad(i * 120.0)
		var body := StaticBody3D.new()
		body.name = "Node%d" % (i + 1)
		body.collision_layer = GameConfig.LAYER_ENEMY
		body.collision_mask = 0
		body.position = Vector3(sin(a) * 4.4, 0.4, cos(a) * 4.4)
		# The metadata is what host_register_hit reads to know which node the
		# ray found; walking the tree by name would break the first time
		# somebody renamed a node.
		body.set_meta("shield_index", i)
		ring.add_child(body)

		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.85
		shape.shape = sphere
		body.add_child(shape)

		var mesh := MeshInstance3D.new()
		mesh.mesh = MeshFactory.crystal(1.5, 0.55, 6)
		body.add_child(mesh)
		ModelKit.set_emission(mesh, Color(0.45, 0.85, 1.0), 1.8)

		# A tether back to the core, so the nodes read as held rather than as
		# three separate things that happen to be nearby.
		ModelKit.emissive(ring, MeshFactory.beveled_box(Vector3(0.07, 0.07, 4.0), 0.02),
			Vector3(sin(a) * 2.2, 0.4, cos(a) * 2.2), Color(0.3, 0.7, 1.0), 0.9,
			Vector3(0.0, rad_to_deg(a), 0.0))


## The power coupling in its cradle: a heavy plug with contact pins and a handle.
## The pins are what say "this goes into something" rather than "this is a box".
static func build_power_coupling(root: Node3D, cradle: MeshInstance3D,
		part: MeshInstance3D) -> void:
	cradle.mesh = MeshFactory.beveled_box(Vector3(1.10, 0.30, 0.86), 0.05)
	cradle.position = Vector3(0.0, 0.15, 0.0)
	ModelKit.set_albedo(cradle, METAL_DARK)

	part.mesh = MeshFactory.beveled_box(Vector3(0.52, 0.44, 0.40), 0.06)
	part.position = Vector3(0.0, 0.52, 0.0)
	ModelKit.set_albedo(part, Color(0.72, 0.58, 0.22))

	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.24, 0.10, 0.98), 0.03),
		Vector3(0.0, 0.05, 0.0), METAL, 0.7, 0.4)
	for sx in [-1.0, 1.0]:
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.09, 0.34, 0.09), 0.02),
			Vector3(sx * 0.5, 0.30, 0.0), TRIM, 0.8, 0.3)
	# Three contact pins on the underside, and a carry handle over the top.
	for i in 3:
		ModelKit.part(root, MeshFactory.tube(0.16, 0.045, 0.028, 8),
			Vector3(-0.14 + i * 0.14, 0.34, 0.0), TRIM, 0.85, 0.25)
	ModelKit.part(root, MeshFactory.torus(0.17, 0.035, 10, 6),
		Vector3(0.0, 0.80, 0.0), METAL_DARK, 0.6, 0.45, Vector3(0.0, 90.0, 0.0))


## The socket the coupling goes into: a housing, a recessed slot, and a status
## bar that is red until it is fed.
static func build_coupling_socket(root: Node3D, housing: MeshInstance3D,
		slot: MeshInstance3D) -> void:
	housing.mesh = MeshFactory.beveled_box(Vector3(1.20, 1.60, 0.70), 0.06)
	housing.position = Vector3(0.0, 0.80, 0.0)
	ModelKit.set_albedo(housing, STONE_DARK)

	slot.mesh = MeshFactory.beveled_box(Vector3(0.56, 0.48, 0.06), 0.02)
	slot.position = Vector3(0.0, 1.02, -0.34)

	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.44, 0.16, 0.94), 0.04),
		Vector3(0.0, 0.08, 0.0), STONE, 0.1, 0.85)
	# A recessed frame around the slot, so it reads as a hole rather than a
	# panel stuck to the front.
	ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.72, 0.64, 0.10), 0.02),
		Vector3(0.0, 1.02, -0.30), METAL_DARK, 0.6, 0.4)
	for sx in [-1.0, 1.0]:
		ModelKit.part(root, MeshFactory.tube(1.30, 0.09, 0.06, 8),
			Vector3(sx * 0.52, 0.80, -0.10), METAL, 0.75, 0.35)
	# Conduit running away into the ground: the socket powers something.
	ModelKit.part(root, MeshFactory.tube(1.80, 0.10, 0.07, 8),
		Vector3(0.0, 0.14, 0.70), METAL, 0.7, 0.4, Vector3(90.0, 0.0, 0.0))


## The vent valve: a wheel on a stack, with hazard striping.
static func build_hazard_control(root: Node3D, housing: MeshInstance3D,
		wheel: MeshInstance3D) -> void:
	housing.mesh = MeshFactory.beveled_box(Vector3(1.00, 1.30, 0.80), 0.05)
	housing.position = Vector3(0.0, 0.65, 0.0)
	ModelKit.set_albedo(housing, METAL_DARK)

	wheel.mesh = MeshFactory.torus(0.34, 0.06, 14, 6)
	wheel.position = Vector3(0.0, 1.20, -0.40)
	wheel.rotation_degrees = Vector3(0.0, 0.0, 0.0)

	ModelKit.part(root, MeshFactory.beveled_box(Vector3(1.24, 0.12, 1.04), 0.03),
		Vector3(0.0, 0.06, 0.0), METAL, 0.7, 0.4)
	# Spokes, so the wheel is a wheel and not a ring floating in the air.
	for i in 4:
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.05, 0.62, 0.05), 0.012),
			Vector3(0.0, 1.20, -0.40), TRIM, 0.8, 0.3,
			Vector3(0.0, 0.0, 45.0 + i * 45.0))
	ModelKit.part(root, MeshFactory.tube(0.30, 0.09, 0.05, 8),
		Vector3(0.0, 1.20, -0.30), TRIM, 0.85, 0.25, Vector3(90.0, 0.0, 0.0))
	# A stack venting upwards, and stripes on the housing.
	ModelKit.part(root, MeshFactory.tube(2.20, 0.24, 0.17, 10),
		Vector3(0.0, 2.10, 0.22), METAL, 0.7, 0.42)
	for i in 3:
		ModelKit.part(root, MeshFactory.beveled_box(Vector3(0.15, 0.36, 0.02), 0.006),
			Vector3(-0.28 + i * 0.28, 0.34, -0.41), Color(0.86, 0.62, 0.16), 0.2, 0.7,
			Vector3(0.0, 0.0, 24.0))
