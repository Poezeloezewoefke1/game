extends TestCase
## Structural checks on the authored level scenes.
##
## These catch the class of mistake that a script-level test never can: a
## duplicated object_id, a pedestal that accepts a crystal nobody placed in the
## level, a missing spawn point, a level with no navigation region. Every one of
## those would present as a mysterious runtime bug rather than a load failure.

## Taken from GameConfig rather than repeated here. The hand-written copy went
## stale the moment the Wayfinder Station became the Starfarer: it kept checking
## a scene file that no longer existed while two new planets went unchecked.
var _levels: Dictionary = {}


func _init() -> void:
	for key in GameConfig.GAMEPLAY_SCENES:
		_levels[String(key)] = GameConfig.scene_path(String(key))


func is_async() -> bool:
	return true


func run_async() -> void:
	_check_player_interact_ray()

	for key in _levels:
		set_current("level:" + String(key))
		await _check_level(String(key), String(_levels[key]))


func _check_level(key: String, path: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if not check(packed != null, "%s loads" % path):
		return
	var level: Node = packed.instantiate()
	tree.root.add_child(level)
	await tree.process_frame

	_check_common(key, level)
	if key == GameConfig.SCENE_SHIP:
		_check_ship(level)
	else:
		await _check_surface(key, level)

	level.queue_free()
	await tree.process_frame
	await tree.process_frame


func _check_common(key: String, level: Node) -> void:
	check_eq(String(level.get("level_key")), key, "%s declares its level_key" % key)

	check(level.get_node_or_null("EntityRoot/EntitySpawner") != null,
		"%s has EntityRoot/EntitySpawner" % key)
	check(level.get_node_or_null("EntityRoot/Entities") != null,
		"%s has EntityRoot/Entities" % key)

	var spawns := level.get_node_or_null("PlayerSpawnPoints")
	if check(spawns != null, "%s has PlayerSpawnPoints" % key):
		check(spawns.get_child_count() >= GameConfig.MAX_PLAYERS,
			"%s has at least %d spawn points (got %d)" % [key, GameConfig.MAX_PLAYERS, spawns.get_child_count()])
		for child in spawns.get_children():
			check(child is Node3D, "%s spawn point %s is a Node3D" % [key, child.name])

	# Every interactable must have a non-empty, unique id and implement the
	# whole contract - a half-implemented interactable fails silently at runtime.
	var seen: Dictionary = {}
	for node in _collect_interactables(level):
		var oid := String(node.get("object_id"))
		check_ne(oid, "", "%s: %s has an object_id" % [key, node.name])
		check_false(seen.has(oid), "%s: object_id '%s' is unique (also on %s)" % [
			key, oid, String(seen.get(oid, ""))])
		seen[oid] = node.name
		# The id must name the level it is IN. Uniqueness within a level is not
		# enough: Cinder's altar and drop pod kept the packed scene's defaults,
		# so both worlds shipped a `nerava_star_map_altar`. Nothing collided,
		# because two levels are never mounted at once - but every caller that
		# builds an id as "<mission>_<thing>" looked for one that did not exist,
		# which is exactly why no automated run had ever finished Cinder.
		check(oid.begins_with(key + "_"),
			"%s: object_id '%s' on %s names its own level" % [key, oid, node.name])
		for method in ["get_interaction_prompt", "can_interact",
				"request_interact", "host_validate_and_apply_interaction",
				"refresh_visual_state", "requires_line_of_sight"]:
			check(node.has_method(method),
				"%s: %s implements %s()" % [key, node.name, method])
		check(node.is_in_group(GameConfig.GROUP_INTERACTABLE),
			"%s: %s is in the Interactable group" % [key, node.name])
		check_eq(node.get("collision_layer"), GameConfig.LAYER_INTERACTABLE,
			"%s: %s is on the interactable physics layer" % [key, node.name])

		# The host validates line of sight to this point before allowing a
		# press. It has to be a point ON the object - the collision shape's
		# centre - and not the origin, which for anything standing on the
		# ground is its feet. Cinder shipped a coupling socket with a piece of
		# set dressing 0.2 m in front of its origin: the prompt appeared, the
		# host refused every press, and the cave crystal was sealed for good.
		if node.has_method("interaction_point"):
			var aim: Vector3 = node.call("interaction_point")
			var origin: Vector3 = (node as Node3D).global_position
			check(aim.distance_to(origin) < 6.0,
				"%s: %s aims the host's check at a point on itself (%.1f m from its origin)"
					% [key, node.name, aim.distance_to(origin)])
			_check_usable_from_somewhere(key, node as Node3D, aim)


## An interactable the host will always refuse is worse than one that is missing.
##
## The host raycasts from the player's chest to the interaction point before
## allowing a press, and refuses if world geometry is in the way. If EVERY
## approach is blocked, the game shows a prompt for something that can never be
## done - which is what Cinder shipped: a ruin pillar 1.0 m from the coupling
## socket, "Press E to Fit Power Coupling" on screen, and five rejections with
## `interact_no_line_of_sight`. The cave crystal behind it was sealed for good
## and the mission was unfinishable, and no test could see it because nothing
## asked this question.
##
## Sampled around the object rather than from one guessed direction: an
## interactable set into a wall is legitimately blocked from three sides, and
## only "blocked from ALL of them" is a defect.
## The probe used to ask the physics server whether a guard post is clear. The
## radius is a little under the guard's own body, so a post that merely brushes
## the scenery is not failed, and the height is chest-high on a hovering guard -
## what is being tested is whether it can be SHOT from across the level.
## Room a solid prop must leave around an interactable. Everything on the three
## levels clears 4.0 m once the three offenders are moved, so this is not a
## number the content is straining against.
const PROP_CLEARANCE: float = 2.5

## How close the hazard field has to stand to the crystal it seals. It is a
## field, not a marker, so this is "over it", not "on it".
const HAZARD_OVER_CRYSTAL: float = 3.0

const GUARD_PROBE_RADIUS: float = 0.8
const GUARD_PROBE_HEIGHT: float = 1.5

const APPROACH_SAMPLES: int = 12
const APPROACH_RANGE: float = 2.6
const APPROACH_CHEST: float = 1.2

func _check_usable_from_somewhere(key: String, node: Node3D, aim: Vector3) -> void:
	if not bool(node.get("needs_line_of_sight")):
		return
	var space := node.get_world_3d().direct_space_state
	if space == null:
		return
	var clear := 0
	for i in APPROACH_SAMPLES:
		var angle: float = TAU * float(i) / float(APPROACH_SAMPLES)
		var stand: Vector3 = node.global_position \
			+ Vector3(cos(angle), 0.0, sin(angle)) * APPROACH_RANGE
		var query := PhysicsRayQueryParameters3D.create(
			stand + Vector3.UP * APPROACH_CHEST, aim)
		query.collision_mask = GameConfig.LAYER_WORLD
		query.collide_with_areas = false
		# A ray that STARTS inside a solid body reports nothing by default, so
		# without this an approach buried in a wall reads as the clearest one of
		# the twelve. That is not a hypothetical: Cinder's and Hallow's grove
		# crystal sits 0.03 m inside GroveBack, every real approach to it is
		# blocked, and this check passed both levels for years because the
		# samples on the far side were inside the wall and answered "clear".
		# The docstring directly below this function is about the player's
		# interact ray needing exactly this flag, for exactly this reason. The
		# check written to catch unusable interactables did not apply the lesson
		# the file already carried.
		query.hit_from_inside = true
		if space.intersect_ray(query).is_empty():
			clear += 1
	check(clear > 0,
		"%s: %s can be used from somewhere - the host's line of sight is clear from %d of %d approaches"
			% [key, node.name, clear, APPROACH_SAMPLES])


## The player's interact ray must report shapes it STARTS INSIDE.
##
## A RayCast3D ignores those by default. The camera sits at y = 1.62 and the
## ship stations' collision boxes run from the deck to y = 1.7, so a player who
## walked right up to a console had their camera inside its box - and the
## prompt vanished at exactly the moment they were closest to it. The automated
## playtest reproduced it as eight consecutive frames of "E held, ray on
## nothing" while standing flush against the fuel station.
func _check_player_interact_ray() -> void:
	set_current("player")
	var packed: PackedScene = load("res://scenes/entities/player.tscn") as PackedScene
	if not check(packed != null, "player.tscn loads"):
		return
	var player := packed.instantiate()
	var ray := player.get_node_or_null("CameraPivot/InteractRay") as RayCast3D
	if check(ray != null, "the player has CameraPivot/InteractRay"):
		check(ray.hit_from_inside,
			"the interact ray reports shapes it starts inside, so standing "
			+ "flush against a console does not hide its prompt")
		check(ray.target_position.length() > 1.0,
			"the interact ray has a usable length (%.1f m)" % ray.target_position.length())
	player.free()


func _check_ship(level: Node) -> void:
	var ids := _ids(level)
	# The pre-flight checklist is only enforceable if every station it names
	# actually exists in the scene. A missing one would leave the launch lever
	# permanently refusing, with nothing to interact with to fix it.
	check(ids.has("ship_nav_console"), "the ship has a nav console")
	check(ids.has("ship_launch_lever"), "the ship has a launch lever")
	for task_id in GameConfig.SHIP_TASK_IDS:
		if String(task_id) == GameConfig.SHIP_TASK_COURSE:
			continue  # plotted at the nav console, not at a station of its own
		check(ids.has("ship_%s" % task_id),
			"the ship has a station for %s" % task_id)
	var seats := 0
	for node in level.find_children("*", "", true, false):
		if node.get("seat_id") != null and String(node.get("seat_id")) != "":
			seats += 1
	check(seats >= GameConfig.MAX_PLAYERS,
		"the ship seats the whole crew (%d seats, %d players)" % [seats, GameConfig.MAX_PLAYERS])
	check_eq(_count_by_property(level, "crystal_id"), 0, "the ship has no crystals")


## Every surface a mission can land on has to satisfy the same contract, or the
## mission that lands there is unwinnable. This used to check only Nerava by
## name, which is exactly why the two new planets shipped without a navmesh.
func _check_surface(key: String, level: Node) -> void:
	var ids := _ids(level)
	check(ids.has("%s_drop_pod" % key) or ids.has("nerava_drop_pod"),
		"%s has a Drop Pod" % key)
	check(_count_by_property(level, "crystal_id") == GameConfig.ALL_CRYSTAL_IDS.size(),
		"%s carries all %d crystals" % [key, GameConfig.ALL_CRYSTAL_IDS.size()])
	check(_count_by_property(level, "pedestal_id") == GameConfig.REQUIRED_PEDESTAL_COUNT,
		"%s has %d pedestals" % [key, GameConfig.REQUIRED_PEDESTAL_COUNT])

	var nav := level.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if check(nav != null, "%s has a NavigationRegion3D" % key):
		check(nav.navigation_mesh != null, "the navigation region has a NavigationMesh")
		check(nav.get_child_count() > 0, "the navigation region actually contains geometry")

	check(level.get_node_or_null("GuardianAnchor") != null, "%s has a GuardianAnchor" % key)
	check(level.get_node_or_null("StarMapDropAnchor") != null,
		"%s has a StarMapDropAnchor" % key)
	check(level.get_node_or_null("StarMapDropAnchor") != null, "Nerava has a StarMapDropAnchor")
	check(level.get_node_or_null("TempleTrigger") != null, "Nerava has a TempleTrigger")

	# --- The puzzle must actually be solvable in this level. ---
	var crystals: Dictionary = {}
	var pedestals: Dictionary = {}
	for node in _collect_interactables(level):
		var cid := String(node.get("crystal_id")) if "crystal_id" in node else ""
		if not cid.is_empty():
			check_false(crystals.has(cid), "crystal '%s' appears exactly once" % cid)
			crystals[cid] = true
		var accepts := String(node.get("accepts_crystal_id")) if "accepts_crystal_id" in node else ""
		if not accepts.is_empty():
			var pid := String(node.get("pedestal_id"))
			check_ne(pid, "", "pedestal %s has a pedestal_id" % node.name)
			check_false(pedestals.has(accepts), "exactly one pedestal accepts '%s'" % accepts)
			pedestals[accepts] = pid

	check_eq(crystals.size(), GameConfig.REQUIRED_PEDESTAL_COUNT,
		"Nerava contains exactly %d crystals" % GameConfig.REQUIRED_PEDESTAL_COUNT)
	check_eq(pedestals.size(), GameConfig.REQUIRED_PEDESTAL_COUNT,
		"Nerava contains exactly %d pedestals" % GameConfig.REQUIRED_PEDESTAL_COUNT)
	for cid in GameConfig.ALL_CRYSTAL_IDS:
		check(crystals.has(cid), "crystal '%s' exists in the level" % cid)
		check(pedestals.has(cid), "a pedestal accepts '%s'" % cid)

	await _check_guard_posts(key, level)
	_check_plateau_approach(key, level)
	_check_locks_agree(key, level)
	_check_prop_clearance(key, level)


## No solid set dressing may stand on top of an interactable.
##
## This is the generalisation of five separate defects, and it should have been
## written after the first. 55: crew-deck furniture on the ship's spine. 56: two
## props narrowing the Nerava approach. 57: a ruin pillar in the only route back
## from the coupling socket. 75: a pillar 1.0 m from that socket, which made the
## host refuse every press and sealed Cinder's cave crystal for good. And then
## the fix for 75 MOVED that pillar to within 1.71 m of the cave crystal, where
## it sat harmlessly until Hallow's guard began the fight on that side - at
## which point the host's ray was blocked and the crystal could not be taken.
##
## Each of those was fixed by moving one prop. None of them added a rule, so the
## next prop was free to land in the same place. The rule is: an interactable
## needs room around it, and the measured levels agree - once these three are
## moved, the closest solid prop to any interactable is 4.0 m.
##
## Nerava has no solid dressing at all, which is exactly why this class of
## defect has never appeared there.
func _check_prop_clearance(key: String, level: Node) -> void:
	var dressing := level.get_node_or_null("NavigationRegion3D/Dressing")
	if dressing == null:
		return
	var solids: Array = []
	for child in dressing.get_children():
		var prop := child as Node3D
		if prop != null and bool(prop.get("solid")):
			solids.append(prop)
	if solids.is_empty():
		return

	# ONE assertion per interactable, against its nearest prop - not one per
	# pair. The pairwise version was correct and reported the same failures, but
	# it added 528 assertions to a suite of 1779 for a single property. The
	# assertion count is quoted in this project as a measure of coverage, so
	# inflating it thirty per cent with the same check repeated is not free: it
	# devalues the number everywhere else it appears.
	for node in _collect_interactables(level):
		var target := node as Node3D
		if target == null:
			continue
		var aim: Vector3 = target.call("interaction_point") \
			if target.has_method("interaction_point") else target.global_position
		var nearest: float = 1000.0
		var nearest_name := ""
		for prop in solids:
			var at: Vector3 = (prop as Node3D).global_position
			var flat: float = Vector2(at.x - aim.x, at.z - aim.z).length()
			if flat < nearest:
				nearest = flat
				nearest_name = String((prop as Node3D).name)
		check(nearest >= PROP_CLEARANCE,
			"%s: %s has %.1f m of room - nearest solid prop is %s at %.2f m"
				% [key, target.name, PROP_CLEARANCE, nearest_name, nearest])


## The level's lock props and the mission's lock table must name the same
## crystals.
##
## `MissionRules.locked_crystals` decides which crystal each lock holds, and the
## level authors the props that release them: a coupling socket carries the
## `unlocks_crystal_id` it powers, and the hazard field stands over the crystal
## it covers. Nothing checked that the two agreed, and they are easy to move
## apart - Hallow's locks were rotated in exactly this way.
##
## A socket pointing at a crystal that is not locked is not a cosmetic error. It
## unlocks nothing, the crystal that IS locked has no way to open, and the
## mission cannot be completed - the same failure as defects 75 and 81, arrived
## at from the data side rather than the geometry side.
func _check_locks_agree(key: String, level: Node) -> void:
	var locks: Dictionary = MissionRules.locked_crystals(key)

	var coupled := ""
	var hazarded := ""
	for crystal_id in locks:
		match String(locks[crystal_id]):
			MissionRules.LOCK_COUPLING: coupled = String(crystal_id)
			MissionRules.LOCK_HAZARD: hazarded = String(crystal_id)

	for node in _collect_interactables(level):
		var unlocks := String(node.get("unlocks_crystal_id")) if "unlocks_crystal_id" in node else ""
		if unlocks.is_empty():
			continue
		check_eq(unlocks, coupled,
			"%s: the coupling socket unlocks the crystal the mission seals behind it" % key)

	if hazarded.is_empty():
		return
	var field := level.get_node_or_null("HazardField") as Node3D
	if not check(field != null, "%s runs a hazard, so it has a HazardField" % key):
		return
	var crystal: Node3D = null
	for node in _collect_interactables(level):
		# Guard the property first. Most interactables are not crystals, and
		# String(null) is an engine error rather than an empty string - which
		# the suite counted as a pass, because a script error does not fail an
		# assertion. That is precisely what run_validation.sh greps the log for.
		if not ("crystal_id" in node):
			continue
		if String(node.get("crystal_id")) == hazarded:
			crystal = node as Node3D
			break
	if not check(crystal != null, "%s has the crystal '%s' its hazard covers" % [key, hazarded]):
		return
	# Flat distance: the field is authored at ground level and the crystal sits
	# on whatever it stands on, so the heights legitimately differ.
	var flat: float = Vector2(field.global_position.x - crystal.global_position.x,
		field.global_position.z - crystal.global_position.z).length()
	check(flat < HAZARD_OVER_CRYSTAL,
		"%s: the hazard field stands over '%s', the crystal it seals (%.1f m away)"
			% [key, hazarded, flat])


## The way up to the temple must match what the navigation bake promises.
##
## Two defects live here, both of which made a planet unfinishable and neither
## of which any test could see. Defect 78: the four "ramps" were boxes topping
## out at 1.05 m, so reaching one was a single 1.05 m step - nothing could climb
## it, not the player and not the bake, and the crystals could be fetched but
## never placed. This is the height half of that.
##
## The width half came later and cost another run. The staircase built to fix 78
## had every tier exactly as wide as the one above it, so a player 0.22 m off
## the centre line was beside the stairs rather than on them, facing the 0.70 m
## SIDE of a step instead of its 0.35 m face - stuck, at 1 hp, carrying the
## crystal home. Each tier now overhangs the one above, and this asserts it,
## because "wide enough" is not something anyone will re-derive by eye the next
## time a block moves.
##
## agent_max_climb is read from the level's own bake rather than repeated here:
## the property is that the geometry and the navigation AGREE, and a copied
## number would let them drift apart silently, which is how 78 happened.
func _check_plateau_approach(key: String, level: Node) -> void:
	var nav := level.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if nav == null or nav.navigation_mesh == null:
		return
	var climb: float = nav.navigation_mesh.agent_max_climb
	var plateau := nav.get_node_or_null("Plateau") as Node3D
	if plateau == null:
		return  # Nerava's temple stands on the ground; there is nothing to climb.

	for side in ["N", "E", "S", "W"]:
		var tiers: Array = []
		for tier_name in ["PlateauStepLow" + side, "PlateauStepMid" + side]:
			var node := nav.get_node_or_null(tier_name) as Node3D
			if node != null:
				tiers.append(node)
		for i in 4:
			var ramp := nav.get_node_or_null("PlateauRamp%d" % (i + 1)) as Node3D
			if ramp != null and _is_on_side(ramp, side):
				tiers.append(ramp)
		tiers.append(plateau)
		if tiers.size() < 3:
			continue

		# The ground the staircase starts from, read from the level rather than
		# assumed to be y = 0. It happens to be 0 on both planets that have a
		# plateau, which is exactly why assuming it would go unnoticed until a
		# level was built at a different height and the first step was measured
		# against nothing - the same "copied number drifts apart" failure that
		# agent_max_climb is read from the bake to avoid.
		var basin := nav.get_node_or_null("Basin") as Node3D
		var previous_top: float = 0.0
		if basin != null:
			var basin_box := _box_of(basin)
			if basin_box != Vector3.ZERO:
				previous_top = basin.global_position.y + basin_box.y * 0.5
		var previous_width: float = 1000.0
		for tier in tiers:
			var box := _box_of(tier as Node3D)
			if box == Vector3.ZERO:
				continue
			var top: float = (tier as Node3D).global_position.y + box.y * 0.5
			check(top - previous_top <= climb + 0.001,
				"%s: %s rises %.2f m from the tier below, within the bake's %.2f m climb"
					% [key, tier.name, top - previous_top, climb])
			# Measured ACROSS the approach, not along it: this is the width that
			# stops a player who has drifted sideways ending up beside the steps.
			#
			# The plateau is exempt, and the first version of this check was
			# wrong to include it. The property is "drift off a tier and you
			# land on the tier below", which is about the staircase; the plateau
			# is the top and the destination, and being 34 m wide is what makes
			# it a temple courtyard rather than a ledge. Asserting the overhang
			# there failed all four approaches on both planets while the levels
			# were correct - a test that fails on good content, which is the
			# thing this suite has now been bitten by twice.
			var width: float = box.x if (side == "N" or side == "S") else box.z
			if tier != plateau:
				check(width <= previous_width + 0.001,
					"%s: %s is %.1f m across, no wider than the %.1f m tier below it"
						% [key, tier.name, width, previous_width])
			previous_top = top
			previous_width = width


func _is_on_side(node: Node3D, side: String) -> bool:
	var at: Vector3 = node.global_position
	match side:
		"N": return at.z < -1.0 and absf(at.x) < 1.0
		"S": return at.z > 1.0 and absf(at.x) < 1.0
		"E": return at.x > 1.0 and absf(at.z) < 1.0
		"W": return at.x < -1.0 and absf(at.z) < 1.0
	return false


## The size of a world block's box, or ZERO if it has none.
func _box_of(node: Node3D) -> Vector3:
	for child in node.find_children("*", "CollisionShape3D", true, false):
		var box := (child as CollisionShape3D).shape as BoxShape3D
		if box != null:
			return box.size
	return Vector3.ZERO


## Every crystal's guard must stand somewhere a player can shoot it.
##
## The defect this exists for: guards were placed at crystal + Vector3(0, 0, 5)
## on every level, and on Cinder and Hallow that is 0.447 m inside RuinsBack, a
## 16 x 8 x 4 wall - so both ruins guards spawned inside solid rock, and nothing
## in this suite had ever asked where a guard ends up. It is not what made those
## two planets unfinishable (that was the playtest driver, see I34 in
## docs/QA_REPORT.md), but it is what wedged the guard in place for as long as
## the Sentinel collided with the world.
##
## The assertion deliberately does NOT reuse SpawnManager's own box arithmetic.
## A test that checks a function against its own reasoning proves only that the
## function is self-consistent, which is exactly what the broken version was.
## This asks the PHYSICS SERVER instead: is there solid world geometry where the
## guard is about to stand?
func _check_guard_posts(key: String, level: Node) -> void:
	# The physics server needs a step with this level in the tree before it can
	# answer. process_frame is not enough.
	await tree.physics_frame
	await tree.physics_frame

	# Only the crystals that ACTUALLY get a guard. The first version asserted
	# this of every crystal on every level and failed four times over on the two
	# crystals that are locked by a coupling and by a hazard - neither of which
	# has anything standing near it. A test that fails on correct content spends
	# attention and returns noise; scene keys are mission ids, so reading the
	# locks here means the check follows the design instead of guessing at it.
	var locks: Dictionary = MissionRules.locked_crystals(key)

	for node in _collect_interactables(level):
		var cid := String(node.get("crystal_id")) if "crystal_id" in node else ""
		if cid.is_empty():
			continue
		if String(locks.get(cid, "")) != MissionRules.LOCK_GUARD:
			continue
		var crystal := node as Node3D
		var post: Vector3 = SpawnManager.guard_post(crystal)

		var space := crystal.get_world_3d().direct_space_state
		if space == null:
			continue
		var shape := SphereShape3D.new()
		shape.radius = GUARD_PROBE_RADIUS
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.collision_mask = GameConfig.LAYER_WORLD
		params.collide_with_areas = false
		params.transform = Transform3D(Basis.IDENTITY, post + Vector3.UP * GUARD_PROBE_HEIGHT)
		var blocking: Array = space.intersect_shape(params, 4)
		var names := PackedStringArray()
		for entry in blocking:
			var collider := (entry as Dictionary).get("collider") as Node
			if collider != null:
				names.append(String(collider.name))
		check(blocking.is_empty(),
			"%s: the guard post for '%s' at %s is clear of the scenery%s" % [
				key, cid, str(post.snapped(Vector3.ONE * 0.1)),
				"" if names.is_empty() else " (inside " + ", ".join(names) + ")"])

		# ...and the crystal it guards must be visible from there, or the guard
		# is standing behind cover rather than in front of what it defends.
		var ray := PhysicsRayQueryParameters3D.create(
			post + Vector3.UP * GUARD_PROBE_HEIGHT,
			crystal.global_position + Vector3.UP * GUARD_PROBE_HEIGHT)
		ray.collision_mask = GameConfig.LAYER_WORLD
		ray.collide_with_areas = false
		ray.hit_from_inside = true
		check(space.intersect_ray(ray).is_empty(),
			"%s: the guard on '%s' can see the crystal it is guarding" % [key, cid])

		# ...and a player must be able to SHOOT it, which is not the same thing
		# and is the property that actually decides whether the level can be
		# finished. The first version of guard_post checked only that a post was
		# clear of the scenery, and moved Nerava's guard - which died in seven
		# volleys - behind RuinColumn2, where sixteen volleys in ninety seconds
		# landed nothing. Two planets fixed by breaking the third, and no gate
		# said a word. This one would have.
		# Traced OUTWARD from the guard, the same property SpawnManager scores,
		# arrived at independently: how far can a shot run along this bearing
		# before it meets scenery? A ring of stances at one fixed radius cannot
		# answer that in a corridor - most of the ring is inside the walls - and
		# a check that cannot tell a good post from a bad one passed Nerava's
		# guard standing directly behind RuinColumn2.
		var body: Vector3 = post + Vector3.UP * GameConfig.GUARDIAN_HOVER_HEIGHT
		var open_bearings := 0
		for i in APPROACH_SAMPLES:
			var angle: float = TAU * float(i) / float(APPROACH_SAMPLES)
			var far: Vector3 = post \
				+ Vector3(cos(angle), 0.0, sin(angle)) * GameConfig.GUARD_SIGHT_RANGE \
				+ Vector3.UP * GameConfig.EYE_HEIGHT
			var shot := PhysicsRayQueryParameters3D.create(body, far)
			shot.collision_mask = GameConfig.LAYER_WORLD
			shot.collide_with_areas = false
			shot.hit_from_inside = true
			var found: Dictionary = space.intersect_ray(shot)
			var reach: float = body.distance_to(far) if found.is_empty() \
				else body.distance_to(found["position"])
			if reach >= GameConfig.GUARD_SIGHT_MIN:
				open_bearings += 1
		check(open_bearings > 0,
			"%s: the guard on '%s' can be shot at from at least %.0f m - %d of %d bearings run clear"
				% [key, cid, GameConfig.GUARD_SIGHT_MIN, open_bearings, APPROACH_SAMPLES])


func _collect_interactables(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Interactable:
			out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out


func _ids(level: Node) -> Dictionary:
	var out: Dictionary = {}
	for node in _collect_interactables(level):
		out[String(node.get("object_id"))] = true
	return out


func _count_by_property(level: Node, property: String) -> int:
	var count := 0
	for node in _collect_interactables(level):
		if property in node and not String(node.get(property)).is_empty():
			count += 1
	return count
