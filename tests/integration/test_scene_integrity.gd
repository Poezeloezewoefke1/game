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
		check(space.intersect_ray(ray).is_empty(),
			"%s: the guard on '%s' can see the crystal it is guarding" % [key, cid])


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
